"""Run focused Swift Testing suites against the engine objects built by SloppyClient.

This avoids SwiftPM loading unrelated WASI command plugins on Windows. It uses
the real AdaText/AdaUI modules and objects, with no source stubs or replacements.
Run after `swift build --product SloppyClient` using the same debug toolchain.
"""
import json
import os
from pathlib import Path
import subprocess

client = Path(__file__).resolve().parents[1]
repo = client.parents[1]
engine = Path(os.environ.get("ADAENGINE_PATH", repo.parent / "AdaEngine"))
build = client / ".build/x86_64-unknown-windows-msvc/debug"
check = repo / ".build/client-engine-functional-check"
check.mkdir(parents=True, exist_ok=True)
description = json.loads((build / "description.json").read_text())
command = description["swiftCommands"]["C.SloppyClient-x86_64-unknown-windows-msvc-debug.module"]
compiler = command["executable"]
other = command["otherArguments"]
compile_args = [compiler, "-parse-as-library", "-enable-testing", "-emit-object", "-whole-module-optimization",
                "-module-name", "EngineFunctionalTests", "-I", str(build / "Modules")]
index = 0
while index < len(other):
    item = other[index]
    if item in ("-Xcc", "-sdk", "-target", "-libc", "-I", "-F"):
        compile_args.extend(other[index:index + 2])
        index += 2
    else:
        index += 1
runner = check / "runner.swift"
runner.write_text("import Testing\n@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }\n")
sources = [engine / "Tests/AdaTextTests/TextMarkdownPluginTests.swift",
           engine / "Tests/AdaUITests/TextMarkdownTests.swift",
           engine / "Tests/AdaUITests/TextSelectionTests.swift",
           engine / "Tests/AdaUITests/TestApplication.swift",
           engine / "Tests/AdaUITests/Helpers/ViewTester.swift",
           client / "Tests/SloppyFeatureChatTests/ChatDraftObservationTests.swift",
           client / "Tests/SloppyFeatureChatTests/ChatComposerSuggestionsTests.swift", runner]
sources.insert(-1, client / "Tests/SloppyClientWorkspaceTests/WorkspaceToolsTests.swift")
obj = check / "EngineFunctionalTests.o"
compile_args.extend(map(str, sources))
compile_args.extend(["-o", str(obj)])
subprocess.run(compile_args, check=True)

manifest = (client / ".build/debug.yaml").read_text()
link_block = manifest.split('  "C.SloppyClient-x86_64-unknown-windows-msvc-debug.exe":', 1)[1]
link_line = next(line.strip()[6:] for line in link_block.splitlines() if line.strip().startswith("args: "))
link_args = json.loads(link_line)
objects_path = next(value[1:] for value in link_args if value.startswith("@"))
objects = Path(objects_path).read_text().splitlines()
# Retain dependent-module specializations emitted into client object files.
# The app entry point is named SloppyClient_main, so removing its linker alias
# below lets the test runner own `main` without executing the application.
objects.append(str(obj))
file_list = check / "Objects.LinkFileList"
file_list.write_text("\n".join(objects) + "\n")
executable = build / "EngineFunctionalTests.exe"
for index, value in enumerate(link_args):
    if value == "-o": link_args[index + 1] = str(executable)
    if value == "-module-name": link_args[index + 1] = "EngineFunctionalTests"
    if value.startswith("@"): link_args[index] = "@" + str(file_list)
alias_index = next((i for i, value in enumerate(link_args) if value.startswith("/ALTERNATENAME:main=")), None)
if alias_index is not None: del link_args[alias_index - 1:alias_index + 1]
subprocess.run(link_args, check=True)
test_env = os.environ.copy()
library_paths = [link_args[i + 1] for i, arg in enumerate(link_args[:-1]) if arg == "-L"]
testing_root = next((parent for path in library_paths for parent in Path(path).parents if parent.name.startswith("Testing-")), None)
if testing_root:
    library_paths.append(str(testing_root / "usr/bin64"))
test_env["PATH"] = os.pathsep.join(library_paths + [test_env.get("PATH", "")])
subprocess.run([str(executable)], check=True, cwd=client, env=test_env)
