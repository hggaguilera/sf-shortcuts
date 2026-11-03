# Records docs/demo.gif for the README with vhs (https://github.com/charmbracelet/vhs).
# Usage, from the repo root:  vhs docs/demo.tape
#
# Runs in a clean zsh (no ~/.zshrc) inside a throwaway SFDX project. sf is replaced by a
# no-op, so nothing is sent to an org; the output shown is the plugin's own (completion and
# the dimmed "→ sf ..." line each shortcut prints).

Output docs/demo.gif

Set Shell zsh
Set FontSize 18
Set Width 1200
Set Height 560
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

Hide
Type "zsh -f" Enter
Type "REPO=$PWD; DEMO=$(mktemp -d)/my-project; mkdir -p $DEMO/force-app/main/default/{classes,lwc/accountCard,lwc/contactList} && cd $DEMO" Enter
Type `print '{"packageDirectories":[{"path":"force-app","default":true}]}' > sfdx-project.json` Enter
Type "for c in AccountService AccountServiceTest ContactService ContactServiceTest; do print x > force-app/main/default/classes/$c.cls; done" Enter
Type "git init -q -b main && git add . && git -c user.name=demo -c user.email=demo@example.com commit -qm init && git checkout -qb feature" Enter
Type "print y >> force-app/main/default/classes/AccountService.cls; print y > force-app/main/default/lwc/accountCard/accountCard.js" Enter
Type "autoload -U compinit && compinit -u; zstyle ':completion:*' menu select; source $REPO/sf-shortcuts.plugin.zsh" Enter
Type "sf() { : }; PROMPT='%F{blue}my-project%f %F{magenta}(feature)%f ❯ '; clear" Enter
Sleep 500ms
Show

# Deploy a class and run its test, completing the test class name with TAB
Type "sfdcls AccountS"
Sleep 400ms
Tab
Sleep 600ms
Type " -t AccountServiceT"
Sleep 400ms
Tab
Sleep 600ms
Enter
Sleep 2s

# Deploy an LWC to another org
Type "sfdlwc acc"
Sleep 400ms
Tab
Sleep 500ms
Type " -o uat"
Sleep 400ms
Enter
Sleep 2s

# Deploy everything changed on this branch, as a dry run
Type "sfdcheck sfdbranch"
Sleep 500ms
Enter
Sleep 3s

# Run a SOQL query
Type `sfq "SELECT Id, Name FROM Account LIMIT 5"`
Sleep 400ms
Enter
Sleep 3s
