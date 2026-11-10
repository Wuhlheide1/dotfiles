# ~/.vault, your locked folder (`vault help`). Going in asks for the password
# with the sudo shape prompt right here; going out, or closing this terminal,
# lets it lock itself once nothing else uses it.
status is-interactive; or return

function vault --description 'go into the vault (asks the password); with arguments: the vault command'
    if test (count $argv) -eq 0
        cd ~/.vault
    else
        # Locking from inside: step out first, or this shell would keep it busy.
        test "$argv[1]" = lock; and __vault_inside_now; and cd ~
        command vault $argv
    end
end

function __vault_inside_now
    test "$PWD" = $HOME/.vault; or string match -q -- "$HOME/.vault/*" "$PWD"
end

function __vault_on_pwd --on-variable PWD
    if __vault_inside_now
        if not mountpoint -q $HOME/.vault
            if not command vault open
                cd -    # cancelled or wrong password: back to where you came from
                return
            end
            cd $PWD     # the cd landed in the empty folder before the vault was mounted
        end
        set -g __vault_inside 1
        command vault seen
    else if set -q __vault_inside
        set -e __vault_inside
        command vault check
    end
end

function __vault_on_exit --on-event fish_exit
    # This shell still sits inside while it exits: check once it is gone.
    set -q __vault_inside; and command vault check --after $fish_pid
end

# A new tab or window opened in the vault's folder starts inside already.
__vault_inside_now; and mountpoint -q $HOME/.vault; and set -g __vault_inside 1
