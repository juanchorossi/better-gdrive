---
name: release
description: "Poner Better GDrive en producción: bump de versión, tests, build e instalación en /Applications, smoke test del app instalado, DMG, commit, push y GitHub Release con el DMG adjunto. Usar cuando el usuario diga /release, \"poné en prod\", \"actualiza todo\", \"sacá release\" o \"publicá la versión\". Invocarlo cuenta como autorización explícita para pushear."
---

# Release de Better GDrive

Flujo completo de "poner en prod". Argumento opcional: la versión nueva
(`/release 1.3.0`). Sin argumento, se hace bump de **patch** sobre la versión
actual de `project.yml`.

Invocar este skill **es** el pedido explícito de push y deploy que exige la
regla global. No volver a preguntar por el push dentro de este flujo. Sí
detenerse si una precondición falla.

Correr todos los pasos desde la raíz del repo. Si un paso falla, parar ahí,
reportar la salida real y no seguir con los siguientes.

## 0. Precondiciones

```bash
git status --short          # debe estar vacío: todo lo que va al release ya está commiteado
git branch --show-current   # main
git fetch --tags origin     # los tags viven en GitHub; el clon local puede no tenerlos
gh auth status              # logueado como juanchorossi
test -x BetterGDrive/Resources/rclone && echo rclone-ok
```

- Si hay cambios sin commitear, parar y pedir que se commiteen primero (o
  commitearlos si el usuario lo pidió en el mismo mensaje).
- Si falta el binario de rclone, parar: el README dice de dónde bajarlo.

## 1. Versión

La fuente de verdad es `project.yml` (`MARKETING_VERSION` y
`CURRENT_PROJECT_VERSION`). El `.pbxproj` se regenera con xcodegen dentro de
`install.sh`, así que **nunca** editar la versión en el `.pbxproj` a mano: se
pisa en el próximo build.

```bash
CURRENT=$(sed -n 's/^ *MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)
```

- Versión nueva = argumento del skill, o `CURRENT` con patch +1.
- Verificar que no exista ya el tag en GitHub:
  `git ls-remote --tags origin "refs/tags/v$NEW"` debe estar vacío.
- Editar `project.yml`: `MARKETING_VERSION: "$NEW"` y
  `CURRENT_PROJECT_VERSION: "$((BUILD + 1))"`.

## 2. Tests

```bash
xcodebuild -scheme BetterGDrive -destination 'platform=macOS' test 2>&1 \
  | grep -E "error:|Test Case.*failed|Executed [0-9]+ tests|TEST (FAILED|SUCCEEDED)" | tail -6
```

Tiene que terminar en `TEST SUCCEEDED` con 0 failures. Si falla, parar: no se
publica con tests rojos.

Aviso conocido: el test host instancia `StatusStore`, que reinicia el daemon
de rclone del puerto 5572. El app instalado pierde su daemon durante la
corrida. No importa: el paso 3 lo reemplaza y relanza igual.

## 3. Build + instalar en /Applications

```bash
./install.sh
```

Hace xcodegen, build Debug firmado con Apple Development, mata la instancia
corriendo, copia a `/Applications/Better GDrive.app` y la lanza. Tiene que
imprimir `✓ Build succeeded` y `✓ Installed`.

## 4. Smoke test del app instalado

Esperar unos segundos y verificar las tres cosas. Si alguna falla, parar.

```bash
sleep 8
APP="/Applications/Better GDrive.app"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"   # == $NEW
test -x "$APP/Contents/Resources/rclone" && echo rclone-bundled      # el DMG tiene que ser autosuficiente
pgrep -x "Better GDrive" >/dev/null && echo app-running
lsof -nP -iTCP:5572 -sTCP:LISTEN | grep -q rclone && echo daemon-listening
```

Si falta `rclone-bundled`, el build no es publicable: hasta 1.2.1 el DMG salía
sin rclone (1,8 MB) y solo andaba en Macs con rclone de Homebrew. El DMG
correcto pesa decenas de MB, no 1,8.

Si las tres pasan, seguir sin preguntar. Si alguna falla, parar y pedirle al
usuario que mire el app en el menú bar antes de publicar nada.

## 5. DMG

```bash
./make-dmg.sh
```

Lee la versión del bundle instalado y se niega a empaquetar si no coincide con
`project.yml`. Produce `BetterGDrive-$NEW.dmg` en la raíz (gitignored).

## 6. Commit del bump

```bash
git add project.yml BetterGDrive.xcodeproj/project.pbxproj
git commit -m "Bump version to $NEW"
```

Agregar la línea de atribución que corresponda a la sesión al final del
mensaje, si hay una indicada.

## 7. Notas de release

Generar desde los commits desde el último tag:

```bash
PREV=$(git tag -l 'v*' | sort -V | tail -1)      # requiere el fetch --tags del paso 0
git log "$PREV"..HEAD --no-merges --pretty='- %s'
NOTES="<scratchpad>/release-notes-$NEW.md"
```

Si `PREV` queda vacío, parar: sin tag previo las notas serían toda la
historia del repo.

Escribir `$NOTES` con el formato de los releases
anteriores: título `## What's new`, subsecciones por tema (`### Status
display`, `### Error messages`, `### Fixes`, etc.), una línea por cambio
visible para el usuario. Omitir los commits de bump y de limpieza interna.
Incluir al final:

```
Debug build signed for development, not notarized: right-click → Open on first launch.
```

## 8. Push + tag + GitHub Release

```bash
git push origin main
git tag "v$NEW" && git push origin "v$NEW"
gh release create "v$NEW" "BetterGDrive-$NEW.dmg" \
  --title "Better GDrive $NEW" \
  --notes-file "$NOTES"
```

El tag va con `v` adelante: el chequeo de updates del app
(`fetchLatestRelease` en `StatusStore.swift`) lee `releases/latest`, le saca
la `v` y compara con `CFBundleShortVersionString`. Un tag sin `v` o un
release marcado como pre-release rompe el aviso de actualización.

## 9. Verificar

```bash
gh release list --limit 3        # v$NEW tiene que figurar como "Latest"
gh api repos/juanchorossi/better-gdrive/releases/latest \
  -q '"\(.tag_name) prerelease=\(.prerelease)", (.assets[] | "\(.name) \(.size/1048576|floor) MB")'
```

Es exactamente lo que consulta el chequeo de updates del app. Tiene que
devolver `v$NEW`, `prerelease=false` y el asset `BetterGDrive-$NEW.dmg` de
decenas de MB.

Nota: `gh release view --json` no tiene campo `isLatest`; por eso se usa
`release list` y la API.

## Reporte final

Decir en una línea cada cosa: versión publicada, resultado de tests, app
instalada y corriendo, URL del release. Si algo se saltó o falló, decirlo
primero y con la salida real.
