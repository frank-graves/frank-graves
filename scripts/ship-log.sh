#!/usr/bin/env bash
# ship-log.sh - Actualiza el README con los últimos proyectos y commits.

set -euo pipefail

USER="frank-graves"
README="README.md"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

# Cabeceras para la API de GitHub
AUTH_HEADER=""
if [ -n "$TOKEN" ]; then
    AUTH_HEADER="Authorization: Bearer $TOKEN"
fi

echo ">> Fetching repos..."
REPOS_JSON=$(curl -s -H "Accept: application/vnd.github+json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "https://api.github.com/users/$USER/repos?per_page=100&sort=pushed")

# Extraer los 5 repos más recientes (excluyendo forks, archivados y el repo del perfil)
PROJECTS=$(echo "$REPOS_JSON" | jq -r --arg user "$USER" '
  [.[] | select(.fork == false and .archived == false and .name != $user)] | 
  .[0:5] | 
  .[] | 
  "> [**\(.name)**](\(.html_url))" + (if .description then " — \(.description)" else "" end)
')

# Extraer el último commit de los 4 proyectos más recientes
ACTIVITY=""
RECENT_REPOS=$(echo "$REPOS_JSON" | jq -r --arg user "$USER" '[.[] | select(.fork == false and .archived == false and .name != $user)][0:4] | .[].name')

for repo in $RECENT_REPOS; do
    COMMIT_JSON=$(curl -s -H "Accept: application/vnd.github+json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "https://api.github.com/repos/$USER/$repo/commits?per_page=1")
    MSG=$(echo "$COMMIT_JSON" | jq -r '.[0].commit.message // empty' | head -n 1 | tr -d '`' | cut -c 1-72)
    DATE=$(echo "$COMMIT_JSON" | jq -r '.[0].commit.author.date // empty' | cut -c 1-10)
    
    if [ -n "$MSG" ]; then
        ACTIVITY="${ACTIVITY}> \`$repo\` <- $MSG <sub>$DATE</sub>\n"
    fi
done

# Fallbacks si no hay datos
if [ -z "$PROJECTS" ]; then PROJECTS="> *Nothing shipped lately. The AI is on vacation.*"; fi
if [ -z "$ACTIVITY" ]; then ACTIVITY="> *Terminal is quiet. Suspiciously quiet.*"; fi

# Función para reemplazar texto entre marcadores usando awk
replace_section() {
    local start_marker="<!-- $1 -->"
    local end_marker="<!-- $2 -->"
    local body="$3"
    
    awk -v start="$start_marker" -v end="$end_marker" -v body="$body" '
        $0 ~ start { print; print body; in_block=1; next }
        $0 ~ end { in_block=0 }
        !in_block { print }
    ' "$README" > "${README}.tmp" && mv "${README}.tmp" "$README"
}

echo ">> Updating README..."
replace_section "AUTO-UPDATE:START" "AUTO-UPDATE:END" "$PROJECTS"
replace_section "ACTIVITY-START" "ACTIVITY-END" "$ACTIVITY"

echo ">> Done."
