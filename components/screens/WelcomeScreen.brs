' Guest landing (TV_APP_SPEC §5 Platform note). Shown before the sign-in keyboard
' for unauthenticated users. Two pill buttons (Sign In / Exit); the screen owns
' focus and key routing, buttons render highlight from m.sel (§12). Selecting
' Sign In raises the `signIn` field (MainScene opens SignInScreen); Exit raises
' `exitApp`.
sub init()
    m.signInBg = m.top.findNode("signInBg")
    m.signInLabel = m.top.findNode("signInLabel")
    m.exitBg = m.top.findNode("exitBg")
    m.exitLabel = m.top.findNode("exitLabel")

    m.sel = 0   ' 0 = Sign In, 1 = Exit
    styleButtons()
    m.top.setFocus(true)
end sub

sub styleButtons()
    if m.sel = 0 then
        m.signInBg.blendColor = "0xC9A84CFF" : m.signInLabel.color = "0x0F1923FF"
        m.exitBg.blendColor   = "0x23324AFF" : m.exitLabel.color   = "0xFFFFFFFF"
    else
        m.signInBg.blendColor = "0x23324AFF" : m.signInLabel.color = "0xFFFFFFFF"
        m.exitBg.blendColor   = "0xC9A84CFF" : m.exitLabel.color   = "0x0F1923FF"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "left" or key = "right" then
        if m.sel = 0 then m.sel = 1 else m.sel = 0
        styleButtons()
        return true
    end if
    if key = "OK" then
        if m.sel = 0 then
            ' Reset-then-set so a return to this screen re-fires the observer.
            m.top.signIn = false
            m.top.signIn = true
        else
            m.top.exitApp = true
        end if
        return true
    end if
    if key = "back" then
        m.top.exitApp = true
        return true
    end if
    return false
end function
