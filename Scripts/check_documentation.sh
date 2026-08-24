#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

link_failures="$(/usr/bin/ruby -ruri -e '
  root = File.expand_path(ARGV.fetch(0))
  files = Dir.glob(File.join(root, "**/*.md")).reject { |path| path.include?("/.build/") }.sort
  failures = []
  files.each do |source|
    text = File.read(source, encoding: "UTF-8")
    targets = text.scan(/\[[^\]]*\]\((?:<([^>]+)>|([^\s\)]+))/).map { |angle, plain| angle || plain }
    targets.each do |target|
      next if target.empty? || target.start_with?("#") || target.match?(/\A(?:https?:|mailto:|tel:)/i)
      path_part = target.split("#", 2).first
      next if path_part.empty?
      resolved = File.expand_path(URI::DEFAULT_PARSER.unescape(path_part), File.dirname(source))
      if !resolved.start_with?(root + File::SEPARATOR) || !File.exist?(resolved)
        failures << "#{source.delete_prefix(root + "/")}: missing or escaping link: #{target}"
      end
    end
  end
  puts failures.uniq.sort
  exit(failures.empty? ? 0 : 1)
' "$module_root")" || {
    printf 'Broken local documentation links:\n%s\n' "$link_failures"
    exit 1
}

for contract in \
    'README.md|Host app подключает этот repository только по надобности' \
    'README.md|bash Scripts/module_gate\.sh' \
    'README.md|https://broadapps-ios-docs\.nkhsnv\.chatgpt\.site' \
    'README.dev.md|Что изменилось и почему' \
    'CHANGELOG.md|что изменилось и почему' \
    'CONTRIBUTING.md|Любой разработчик может'
do
    contract_file="${contract%%|*}"
    contract_pattern="${contract#*|}"
    if ! rg -q -- "$contract_pattern" "$module_root/$contract_file"; then
        echo "Documentation contract is missing: $contract_file -> $contract_pattern"
        exit 1
    fi
done

echo "Documentation links and module contracts are valid."
