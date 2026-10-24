#!/usr/bin/env python3
"""Generate SDK-owned Windows/Android runners without overwriting application code."""
import shutil
import subprocess
from pathlib import Path


def main():
    client = Path(__file__).resolve().parents[1] / "client"
    flutter = shutil.which("flutter")
    if not flutter:
        raise SystemExit("Install Flutter stable and add flutter to PATH, then run this script again.")
    # Flutter creates the platform files matching the installed SDK, including its
    # Gradle wrapper and Windows CMake files. Existing Dart sources are preserved.
    protected = {path: path.read_bytes() for path in [client / "pubspec.yaml", *sorted((client / "lib").glob("*.dart"))]}
    try:
        subprocess.run([flutter, "create", "--platforms=android,windows", "--org", "org.resonance",
                        "--project-name", "resonance", "--no-pub", "."], cwd=client, check=True)
    finally:
        for path, content in protected.items():
            path.write_bytes(content)
    # Remove Flutter's generated counter-app test; our tests live under test/.
    generated_test = client / "test" / "widget_test.dart"
    if generated_test.exists() and "MyApp" in generated_test.read_text():
        generated_test.unlink()
    manifest = client / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    shutil.copyfile(client / "platform_config" / "AndroidManifest.xml", manifest)
    native_sources = client / "platform_config" / "android"
    kotlin = client / "android" / "app" / "src" / "main" / "kotlin" / "org" / "resonance" / "resonance"
    kotlin.mkdir(parents=True, exist_ok=True)
    for source in native_sources.glob("*.kt"):
        shutil.copyfile(source, kotlin / source.name)
    tests = client / "android" / "app" / "src" / "androidTest"
    test_kotlin = tests / "kotlin" / "org" / "resonance" / "resonance"
    test_kotlin.mkdir(parents=True, exist_ok=True)
    for source in (client / "platform_config" / "androidtests").glob("*.kt"):
        shutil.copyfile(source, test_kotlin / source.name)
    shutil.copytree(client / "platform_config" / "androidtests" / "assets", tests / "assets", dirs_exist_ok=True)
    gradle = client / "android" / "app" / "build.gradle.kts"
    begin = "// BEGIN RESONANCE NATIVE AUDIO"
    content = gradle.read_text()
    if begin in content:
        content = content[:content.index(begin)].rstrip() + "\n"
    content += "\n" + begin + "\n" + (native_sources / "native.gradle.kts").read_text() + "\n// END RESONANCE NATIVE AUDIO\n"
    gradle.write_text(content)
    subprocess.run([flutter, "pub", "get"], cwd=client, check=True)
    print("Ready. Run flutter analyze, flutter test, and flutter run -d windows (or an Android device) in client/.")


if __name__ == "__main__":
    main()
