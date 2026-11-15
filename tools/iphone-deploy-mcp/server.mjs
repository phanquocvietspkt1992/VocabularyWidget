import { spawn, execFile } from "node:child_process";
import { createWriteStream } from "node:fs";
import { access, mkdir, mkdtemp, readFile, readdir, rename, writeFile } from "node:fs/promises";
import { X509Certificate, randomUUID } from "node:crypto";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const SERVER_DIR = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE_ROOT = path.resolve(SERVER_DIR, "../..");
const PROJECT_PATH = path.join(WORKSPACE_ROOT, "VocabularyWidget.xcodeproj");
const SKILL_PATH = path.join(WORKSPACE_ROOT, ".agents/skills/iphone-device-build/SKILL.md");
const BUILD_ROOT = "/private/tmp/VocabularyWidgetBuilds";
const STATE_DIR = path.join(os.homedir(), "Library/Application Support/VocabularyWidget/iphone-deploy-mcp");
const LEDGER_PATH = path.join(STATE_DIR, "deployments.json");
const TEAM_ID = "PD2729ZJNT";
const APP_BUNDLE_ID = "com.phanquocviet.VocabularyWidget";
const EXTENSION_BUNDLE_ID = `${APP_BUNDLE_ID}.WidgetKit`;
const APP_GROUP = "group.com.phanquocviet.VocabularyWidget";
const APP_ENTITLEMENTS = path.join(WORKSPACE_ROOT, "App/VocabularyWidget.entitlements");
const EXTENSION_ENTITLEMENTS = path.join(WORKSPACE_ROOT, "Widget/VocabularyWidgetExtension.entitlements");

function capture(command, args, options = {}) {
  return new Promise((resolve) => {
    execFile(command, args, {
      cwd: options.cwd ?? WORKSPACE_ROOT,
      encoding: "utf8",
      maxBuffer: 128 * 1024 * 1024,
      env: process.env,
    }, (error, stdout, stderr) => {
      resolve({
        exitCode: error ? (typeof error.code === "number" ? error.code : 1) : 0,
        stdout: stdout ?? "",
        stderr: stderr ?? "",
        error: error?.message ?? null,
      });
    });
  });
}

async function requireCommand(command, args, label, options) {
  const result = await capture(command, args, options);
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed (exit ${result.exitCode}): ${result.stderr || result.stdout || result.error}`);
  }
  return result;
}

async function runToLog(command, args, cwd, logPath) {
  const log = createWriteStream(logPath, { flags: "wx" });
  const child = spawn(command, args, { cwd, env: process.env, stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.on("data", (chunk) => log.write(chunk));
  child.stderr.on("data", (chunk) => log.write(chunk));
  const result = await new Promise((resolve) => {
    child.once("error", (error) => resolve({ exitCode: null, error: error.message }));
    child.once("close", (exitCode, signal) => resolve({ exitCode, signal, error: null }));
  });
  await new Promise((resolve, reject) => {
    log.once("error", reject);
    log.end(resolve);
  });
  return result;
}

async function tailFile(filePath, count = 35) {
  try {
    return (await readFile(filePath, "utf8")).trimEnd().split(/\r?\n/).slice(-count).join("\n");
  } catch {
    return "(log unavailable)";
  }
}

async function writeJsonAtomic(filePath, value) {
  await mkdir(path.dirname(filePath), { recursive: true });
  const temporaryPath = `${filePath}.${randomUUID()}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, { flag: "wx" });
  await rename(temporaryPath, filePath);
}

function dateParts(value) {
  const match = /^(\d{4})\.(\d{1,2})\.(\d{1,2})$/.exec(value ?? "");
  if (!match) throw new Error(`Invalid deployment date: ${value}`);
  const [, yearText, monthText, dayText] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const verified = new Date(Date.UTC(year, month - 1, day));
  if (verified.getUTCFullYear() !== year || verified.getUTCMonth() !== month - 1 || verified.getUTCDate() !== day) {
    throw new Error(`Invalid deployment date: ${value}`);
  }
  return { year, month, day };
}

export function nextBuildNumber(today, lastDeployment) {
  dateParts(today);
  if (!lastDeployment || lastDeployment.date !== today) return 1;
  const buildNumber = Number(lastDeployment.buildNumber);
  if (!Number.isInteger(buildNumber) || buildNumber < 1) {
    throw new Error("Last successful deployment has an invalid build number.");
  }
  return buildNumber + 1;
}

export function parseLegacyDeployment(skillText) {
  const lines = skillText.split(/\r?\n/).filter((line) => line.includes("Successful physical deployment:"));
  const line = lines.at(-1);
  if (!line) return null;
  const versionMatch = /Successful physical deployment:\s*`(\d{4}\.\d{1,2}\.\d{1,2})`\s*\/\s*`(\d+)`/.exec(line);
  const evidenceMatch = /Evidence:\s*`([^`]+)`/.exec(line);
  if (!versionMatch || !evidenceMatch) {
    throw new Error("The latest successful deployment note is incomplete; resolve its version and evidence before deploying.");
  }
  const { year, month, day } = dateParts(versionMatch[1]);
  return {
    date: versionMatch[1],
    buildNumber: Number(versionMatch[2]),
    evidenceDirectory: evidenceMatch[1],
    source: "skill-history",
    deployedAt: `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}T00:00:00.000Z`,
  };
}

export function deviceAvailability(output, udid) {
  const lines = output.split(/\r?\n/);
  const index = lines.findIndex((line) => line.includes(udid));
  if (index < 0) return { found: false, connected: false, physical: false, detail: "Device UDID is not listed." };
  const detail = lines.slice(index, index + 3).join(" ").trim();
  return {
    found: true,
    connected: /\bconnected\b/i.test(detail),
    physical: /\bphysical\b/i.test(detail),
    detail,
  };
}

async function localDate() {
  const result = await requireCommand("/bin/date", ["+%Y.%-m.%-d %Z"], "Read local date");
  const [date, timezone] = result.stdout.trim().split(/\s+/, 2);
  dateParts(date);
  return { date, timezone };
}

function setting(output, key, fallback) {
  const matches = [...output.matchAll(new RegExp(`^\\s*${key}\\s*=\\s*(.*?)\\s*$`, "gm"))];
  const values = [...new Set(matches.map((match) => match[1]))];
  if (values.length === 0 && fallback !== undefined) return fallback;
  if (values.length !== 1) throw new Error(`Expected one ${key} build setting, found ${values.length}.`);
  return values[0];
}

async function signingIdentity() {
  const identities = await requireCommand("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"], "Inspect signing identities");
  const identityLines = [...identities.stdout.matchAll(/^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"(Apple Development:[^"]+)"/gm)];
  const certificates = await requireCommand("/usr/bin/security", ["find-certificate", "-a", "-c", "Apple Development", "-p"], "Read Apple Development certificates");
  const pemBlocks = certificates.stdout.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g) ?? [];
  const parsedCertificates = pemBlocks.map((pem) => new X509Certificate(pem));
  for (const [, fingerprint, name] of identityLines) {
    const certificate = parsedCertificates.find((item) => item.fingerprint.replaceAll(":", "").toLowerCase() === fingerprint.toLowerCase());
    const team = certificate?.subject.match(/^OU=([^,\n]+)$/m)?.[1];
    if (team === TEAM_ID) return { name, teamId: team, fingerprint };
  }
  throw new Error(`No valid Apple Development signing identity for configured team ${TEAM_ID} was found.`);
}

async function deviceList() {
  const result = await capture("/usr/bin/xcrun", ["devicectl", "list", "devices"]);
  return { ...result, devices: result.exitCode === 0 ? result.stdout : "" };
}

async function inspectPreflight() {
  const [date, developerDirectory, identity] = await Promise.all([
    localDate(),
    requireCommand("/usr/bin/xcode-select", ["-p"], "Locate Xcode"),
    signingIdentity(),
  ]);
  const deviceResult = await deviceList();
  const appSettings = await requireCommand("/usr/bin/xcodebuild", [
    "-project", PROJECT_PATH, "-target", "VocabularyWidgetApp",
    "-configuration", "Release", "-showBuildSettings",
  ], "Inspect app build settings");
  const extensionSettings = await requireCommand("/usr/bin/xcodebuild", [
    "-project", PROJECT_PATH, "-target", "VocabularyWidgetExtension",
    "-configuration", "Release", "-showBuildSettings",
  ], "Inspect extension build settings");
  const project = {
    teamIds: [setting(appSettings.stdout, "DEVELOPMENT_TEAM"), setting(extensionSettings.stdout, "DEVELOPMENT_TEAM")],
    bundleIds: [setting(appSettings.stdout, "PRODUCT_BUNDLE_IDENTIFIER"), setting(extensionSettings.stdout, "PRODUCT_BUNDLE_IDENTIFIER")],
    signingStyles: [setting(appSettings.stdout, "CODE_SIGN_STYLE", "Automatic"), setting(extensionSettings.stdout, "CODE_SIGN_STYLE", "Automatic")],
  };
  if (project.teamIds.some((team) => team !== TEAM_ID) || identity.teamId !== TEAM_ID) {
    throw new Error("Configured project team and verified signing identity do not match the approved team.");
  }
  if (project.bundleIds[0] !== APP_BUNDLE_ID || project.bundleIds[1] !== EXTENSION_BUNDLE_ID) {
    throw new Error("Project bundle identifiers differ from the approved VocabularyWidget identifiers.");
  }
  if (project.signingStyles.some((style) => style !== "Automatic")) {
    throw new Error("Both iOS targets must use automatic signing for this deployment workflow.");
  }
  for (const entitlementPath of [APP_ENTITLEMENTS, EXTENSION_ENTITLEMENTS]) {
    const group = await requireCommand("/usr/libexec/PlistBuddy", ["-c", "Print :com.apple.security.application-groups:0", entitlementPath], "Read App Group entitlement");
    if (group.stdout.trim() !== APP_GROUP) throw new Error(`Unexpected App Group in ${entitlementPath}.`);
  }
  const git = await capture("/usr/bin/git", ["status", "--short"]);
  const history = await deploymentHistory();
  const lastDeployment = history.deployments.at(-1);
  const buildNumber = nextBuildNumber(date.date, lastDeployment);
  return {
    date,
    developerDirectory: developerDirectory.stdout.trim(),
    identity,
    project,
    deviceList: deviceResult.exitCode === 0 ? deviceResult.stdout.trim() : null,
    deviceError: deviceResult.exitCode === 0 ? null : deviceResult.stderr || deviceResult.error,
    worktreeChanges: git.stdout.trim() ? git.stdout.trim().split(/\r?\n/) : [],
    lastSuccessfulDeployment: lastDeployment,
    nextVersion: { marketingVersion: date.date, buildNumber },
    buildRoot: BUILD_ROOT,
    statePath: LEDGER_PATH,
  };
}

async function ensureLegacyEvidence(deployment) {
  if (!deployment || deployment.source !== "skill-history") return;
  const required = ["xcodebuild.log", "install.log", "launch.log"];
  for (const filename of required) {
    try {
      await access(path.join(deployment.evidenceDirectory, filename));
    } catch {
      throw new Error(`Deployment history is present but its evidence is missing: ${path.join(deployment.evidenceDirectory, filename)}`);
    }
  }
}

function dateOrder(value) {
  const { year, month, day } = dateParts(value);
  return Date.UTC(year, month - 1, day);
}

export function mergeDeploymentHistory(deployments, legacy) {
  const merged = [...deployments];
  if (legacy && !merged.some((item) => item.date === legacy.date && Number(item.buildNumber) === legacy.buildNumber)) {
    merged.push(legacy);
  }
  return merged.sort((a, b) => dateOrder(a.date) - dateOrder(b.date)
    || Number(a.buildNumber) - Number(b.buildNumber)
    || (Date.parse(a.deployedAt ?? "") || 0) - (Date.parse(b.deployedAt ?? "") || 0));
}

async function deploymentHistory() {
  let deployments = [];
  try {
    const stored = JSON.parse(await readFile(LEDGER_PATH, "utf8"));
    if (!Array.isArray(stored.deployments)) throw new Error("Deployment ledger has no deployments array.");
    deployments = stored.deployments;
  } catch (error) {
    if (error.code !== "ENOENT") throw new Error(`Cannot read deployment ledger: ${error.message}`);
  }
  for (const deployment of deployments) {
    if (!deployment || !Number.isInteger(Number(deployment.buildNumber)) || Number(deployment.buildNumber) < 1) {
      throw new Error("Deployment ledger contains an invalid successful deployment record.");
    }
    dateParts(deployment.date);
  }
  const skillText = await readFile(SKILL_PATH, "utf8");
  const legacy = parseLegacyDeployment(skillText);
  if (legacy) {
    await ensureLegacyEvidence(legacy);
    deployments = mergeDeploymentHistory(deployments, legacy);
  } else if (deployments.length === 0) {
    throw new Error("No successful deployment evidence is recorded; refusing to guess the next build number.");
  }
  try {
    const directoryNames = (await readdir(BUILD_ROOT, { withFileTypes: true }))
      .filter((entry) => entry.isDirectory() && /^iphone-\d{8}-[A-Za-z0-9]+$/.test(entry.name));
    for (const entry of directoryNames) {
      try {
        const manifest = JSON.parse(await readFile(path.join(BUILD_ROOT, entry.name, "deployment.json"), "utf8"));
        if (manifest.launch?.success) {
          if (!manifest.deploymentRecord) throw new Error(`Successful launch manifest is incomplete: ${entry.name}`);
          if (!deployments.some((item) => item.buildId === manifest.buildId)) deployments.push(manifest.deploymentRecord);
        }
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  return { deployments: mergeDeploymentHistory(deployments, null) };
}

async function saveManifest(buildDirectory, manifest) {
  await writeJsonAtomic(path.join(buildDirectory, "deployment.json"), manifest);
}

async function loadManifest(buildId) {
  if (!/^iphone-\d{8}-[A-Za-z0-9]+$/.test(buildId)) throw new Error("Invalid build ID.");
  const buildDirectory = path.resolve(BUILD_ROOT, buildId);
  if (path.dirname(buildDirectory) !== BUILD_ROOT) throw new Error("Build directory is outside the approved build root.");
  const manifest = JSON.parse(await readFile(path.join(buildDirectory, "deployment.json"), "utf8"));
  if (manifest.buildId !== buildId || manifest.buildDirectory !== buildDirectory || manifest.buildSucceeded !== true) {
    throw new Error("Build manifest is invalid or does not record a successful build.");
  }
  return { buildDirectory, manifest };
}

async function validateBuiltApp(appPath, version, buildNumber) {
  const extensionPath = path.join(appPath, "PlugIns/VocabularyWidgetExtension.appex");
  for (const [bundlePath, expectedBundle] of [[appPath, APP_BUNDLE_ID], [extensionPath, EXTENSION_BUNDLE_ID]]) {
    const bundleId = await requireCommand("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleIdentifier", path.join(bundlePath, "Info.plist")], "Read built bundle identifier");
    const marketing = await requireCommand("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleShortVersionString", path.join(bundlePath, "Info.plist")], "Read built marketing version");
    const build = await requireCommand("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleVersion", path.join(bundlePath, "Info.plist")], "Read built version number");
    if (bundleId.stdout.trim() !== expectedBundle || marketing.stdout.trim() !== version || build.stdout.trim() !== String(buildNumber)) {
      throw new Error(`Built bundle metadata mismatch in ${bundlePath}.`);
    }
    await requireCommand("/usr/bin/codesign", ["--verify", "--strict", "--verbose=2", bundlePath], "Verify built bundle signature");
    const details = await requireCommand("/usr/bin/codesign", ["-dv", "--verbose=4", bundlePath], "Inspect built bundle signature");
    const detailText = `${details.stdout}\n${details.stderr}`;
    if (!detailText.includes(`Identifier=${expectedBundle}`) || !detailText.includes(`TeamIdentifier=${TEAM_ID}`)) {
      throw new Error(`Built signature team or identifier mismatch in ${bundlePath}.`);
    }
    const entitlements = await requireCommand("/usr/bin/codesign", ["-d", "--entitlements", ":-", bundlePath], "Inspect signed entitlements");
    if (!entitlements.stdout.includes(APP_GROUP)) throw new Error(`Built bundle lacks the approved App Group: ${bundlePath}`);
  }
  await requireCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath], "Verify complete app signature");
  return { appPath, extensionPath };
}

async function buildApp() {
  const state = await inspectPreflight();
  const { marketingVersion, buildNumber } = state.nextVersion;
  await mkdir(BUILD_ROOT, { recursive: true });
  const buildDirectory = await mkdtemp(path.join(BUILD_ROOT, `iphone-${state.date.date.replaceAll(".", "")}-`));
  const buildId = path.basename(buildDirectory);
  const derivedDataPath = path.join(buildDirectory, "derived-data");
  const logPath = path.join(buildDirectory, "xcodebuild.log");
  const args = [
    "-project", PROJECT_PATH,
    "-scheme", "VocabularyWidgetApp",
    "-configuration", "Release",
    "-destination", "generic/platform=iOS",
    "-derivedDataPath", derivedDataPath,
    "-allowProvisioningUpdates",
    `DEVELOPMENT_TEAM=${TEAM_ID}`,
    "CODE_SIGN_STYLE=Automatic",
    "CODE_SIGN_IDENTITY=Apple Development",
    `MARKETING_VERSION=${marketingVersion}`,
    `CURRENT_PROJECT_VERSION=${buildNumber}`,
    "build",
  ];
  const startedAt = new Date().toISOString();
  const processResult = await runToLog("/usr/bin/xcodebuild", args, WORKSPACE_ROOT, logPath);
  const logTail = await tailFile(logPath);
  const buildSucceeded = processResult.exitCode === 0 && (await readFile(logPath, "utf8")).includes("** BUILD SUCCEEDED **");
  const appPath = path.join(derivedDataPath, "Build/Products/Release-iphoneos/VocabularyWidgetApp.app");
  let validation = null;
  let validationError = null;
  if (buildSucceeded) {
    try {
      validation = await validateBuiltApp(appPath, marketingVersion, buildNumber);
    } catch (error) {
      validationError = error.message;
    }
  }
  const manifest = {
    schemaVersion: 1,
    buildId,
    buildDirectory,
    startedAt,
    builtAt: new Date().toISOString(),
    date: marketingVersion,
    buildNumber,
    teamId: TEAM_ID,
    appBundleId: APP_BUNDLE_ID,
    extensionBundleId: EXTENSION_BUNDLE_ID,
    appGroup: APP_GROUP,
    buildSucceeded,
    buildExitCode: processResult.exitCode,
    processError: processResult.error,
    appPath,
    validation,
    validationError,
    buildLog: logPath,
    installed: {},
    launch: null,
  };
  await saveManifest(buildDirectory, manifest);
  if (!buildSucceeded || validationError) {
    throw new Error(`Signed build or artifact verification failed. Evidence: ${buildDirectory}\n${validationError ?? processResult.error ?? logTail}`);
  }
  return {
    buildId,
    version: `${marketingVersion}/${buildNumber}`,
    buildDirectory,
    appPath,
    buildLog: logPath,
    signatureAndMetadata: "verified for host and embedded extension",
    buildWarnings: (await tailFile(logPath, 500)).split(/\r?\n/).filter((line) => /warning:/i.test(line)).slice(-20),
    worktreeChanges: state.worktreeChanges,
  };
}

async function verifyPendingBuild(manifest) {
  const state = await inspectPreflight();
  const current = state.nextVersion;
  if (manifest.date !== current.marketingVersion || manifest.buildNumber !== current.buildNumber) {
    throw new Error(`This build is no longer the pending version. Rebuild as ${current.marketingVersion}/${current.buildNumber}.`);
  }
  await validateBuiltApp(manifest.appPath, manifest.date, manifest.buildNumber);
  return current;
}

async function requireConnectedPhysicalDevice(udid) {
  const listing = await deviceList();
  if (listing.exitCode !== 0) throw new Error(`Could not list devices: ${listing.stderr || listing.error}`);
  const availability = deviceAvailability(listing.stdout, udid);
  if (!availability.found || !availability.connected || !availability.physical) {
    throw new Error(`Target must be a connected physical iPhone. devicectl reported: ${availability.detail}\n${listing.stdout.trim()}`);
  }
  return availability;
}

async function installApp(buildId, deviceUdid) {
  const { buildDirectory, manifest } = await loadManifest(buildId);
  await verifyPendingBuild(manifest);
  await requireConnectedPhysicalDevice(deviceUdid);
  const logPath = path.join(buildDirectory, "install.log");
  const result = await runToLog("/usr/bin/xcrun", ["devicectl", "device", "install", "app", "--device", deviceUdid, manifest.appPath], WORKSPACE_ROOT, logPath);
  if (result.exitCode !== 0) {
    manifest.installed[deviceUdid] = { success: false, exitCode: result.exitCode, logPath, attemptedAt: new Date().toISOString() };
    await saveManifest(buildDirectory, manifest);
    throw new Error(`Installation failed. Evidence: ${logPath}\n${await tailFile(logPath)}`);
  }
  manifest.installed[deviceUdid] = { success: true, logPath, installedAt: new Date().toISOString() };
  await saveManifest(buildDirectory, manifest);
  return { buildId, deviceUdid, installed: true, version: `${manifest.date}/${manifest.buildNumber}`, logPath, log: await tailFile(logPath, 15) };
}

async function launchApp(buildId, deviceUdid) {
  const { buildDirectory, manifest } = await loadManifest(buildId);
  if (!manifest.installed?.[deviceUdid]?.success) throw new Error("Install this verified build on the selected device before launching it.");
  await verifyPendingBuild(manifest);
  await requireConnectedPhysicalDevice(deviceUdid);
  const logPath = path.join(buildDirectory, "launch.log");
  const result = await runToLog("/usr/bin/xcrun", ["devicectl", "device", "process", "launch", "--device", deviceUdid, APP_BUNDLE_ID], WORKSPACE_ROOT, logPath);
  manifest.launch = {
    success: result.exitCode === 0,
    exitCode: result.exitCode,
    deviceUdid,
    logPath,
    launchedAt: result.exitCode === 0 ? new Date().toISOString() : null,
    attemptedAt: new Date().toISOString(),
  };
  if (result.exitCode !== 0) {
    await saveManifest(buildDirectory, manifest);
    throw new Error(`Launch failed; this build counter remains pending. Retry launch after resolving the device issue. Evidence: ${logPath}\n${await tailFile(logPath)}`);
  }
  const record = {
    date: manifest.date,
    buildNumber: manifest.buildNumber,
    deployedAt: manifest.launch.launchedAt,
    deviceUdid,
    buildId,
    evidenceDirectory: buildDirectory,
    buildLog: manifest.buildLog,
    installLog: manifest.installed[deviceUdid].logPath,
    launchLog: logPath,
    source: "mcp",
  };
  manifest.deploymentRecord = record;
  await saveManifest(buildDirectory, manifest);
  const history = await deploymentHistory();
  if (!history.deployments.some((item) => item.buildId === buildId)) history.deployments.push(record);
  try {
    await writeJsonAtomic(LEDGER_PATH, { schemaVersion: 1, deployments: history.deployments });
  } catch (error) {
    return {
      buildId,
      launched: true,
      version: `${manifest.date}/${manifest.buildNumber}`,
      deviceUdid,
      logPath,
      ledgerWarning: `App launch succeeded, but the local ledger could not be updated: ${error.message}. The successful manifest remains in ${buildDirectory}.`,
    };
  }
  return { buildId, launched: true, version: `${manifest.date}/${manifest.buildNumber}`, deviceUdid, logPath, counterConsumed: true };
}

async function status() {
  const date = await localDate();
  const history = await deploymentHistory();
  const lastDeployment = history.deployments.at(-1);
  return {
    today: date,
    lastSuccessfulDeployment: lastDeployment,
    nextVersion: { marketingVersion: date.date, buildNumber: nextBuildNumber(date.date, lastDeployment) },
    ledgerPath: LEDGER_PATH,
    buildRoot: BUILD_ROOT,
  };
}

const server = new McpServer({ name: "vocabularywidget-iphone-deploy", version: "1.0.0" });

function register(name, description, inputSchema, handler) {
  server.registerTool(name, { description, inputSchema }, async (input) => {
    try {
      const result = await handler(input);
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    } catch (error) {
      return { isError: true, content: [{ type: "text", text: error.message }] };
    }
  });
}

register("iphone_preflight", "Check Xcode, the approved signing team, app identifiers, entitlements, deployment history, worktree changes, and paired devices. Does not build or change the device.", {}, inspectPreflight);
register("iphone_build", "Create a fresh signed Release iPhone build with the next evidence-based version. Automatic provisioning may contact Apple. Does not install or launch.", {}, buildApp);
register("iphone_install", "Install a verified MCP-created build in place on a connected physical iPhone. Does not uninstall the app or reset its data. Installing overwrites the app bundle.", {
  buildId: z.string().regex(/^iphone-\d{8}-[A-Za-z0-9]+$/),
  deviceUdid: z.string().min(12).max(64),
}, ({ buildId, deviceUdid }) => installApp(buildId, deviceUdid));
register("iphone_launch", "Launch a build previously installed by this MCP on the same connected physical iPhone. Only a successful launch consumes the version counter.", {
  buildId: z.string().regex(/^iphone-\d{8}-[A-Za-z0-9]+$/),
  deviceUdid: z.string().min(12).max(64),
}, ({ buildId, deviceUdid }) => launchApp(buildId, deviceUdid));
register("iphone_deployment_status", "Show the last evidenced successful deployment, today's pending version, and local evidence locations. Does not modify anything.", {}, status);

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}