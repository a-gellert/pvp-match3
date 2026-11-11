#!/bin/sh
set -e
DEFOLD=${DEFOLD:-"C:/Program Files (x86)/Defold"}
[ -d "$DEFOLD" ] || DEFOLD="C:/Defold"
JAVA=$(ls -d "$DEFOLD"/packages/jdk-*/bin/java.exe | tail -1)
JAR=$(ls "$DEFOLD"/packages/defold-*.jar | head -1)
rm -rf bundle/release
"$JAVA" -cp "$JAR" com.dynamo.bob.Bob --root . --platform wasm-web --architectures wasm-web \
  --variant release --archive --experimental-path-minification --bundle-output bundle/release resolve build bundle
DIR=$(ls -d bundle/release/*/ | head -1)
rm -f poki.zip
powershell.exe -NoProfile -Command "Compress-Archive -Path '${DIR}*' -DestinationPath 'poki.zip' -Force"
ls -la poki.zip
