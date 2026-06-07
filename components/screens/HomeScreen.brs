' Placeholder Home. Confirms the bearer token works and offers sign-out.
' Full Home per TV_APP_SPEC §6 is a later pass.

sub init()
    m.welcome = m.top.findNode("welcome")
    m.subtitle = m.top.findNode("subtitle")
    m.signOutBtn = m.top.findNode("signOutBtn")
    m.signOutBtn.observeField("buttonSelected", "onSignOut")
    m.signOutBtn.setFocus(true)

    m.meTask = CreateObject("roSGNode", "ApiTask")
    m.meTask.observeField("response", "onMeResponse")
    m.meTask.request = ApiReq().me()
    m.meTask.control = "RUN"
end sub

sub onMeResponse()
    resp = m.meTask.response
    if resp = invalid then return

    ' A 401 with a token present means the token is dead → back to Pairing. §2
    if resp.status = 401 then
        m.top.signedOut = true
        return
    end if

    if resp.ok = true then
        user = invalid
        if resp.data <> invalid then user = resp.data.user
        name = "there"
        if user <> invalid then
            if user.display_name <> invalid and user.display_name <> "" then
                name = user.display_name
            else if user.name <> invalid and user.name <> "" then
                name = user.name
            end if
        end if
        m.welcome.text = "Welcome, " + name
        m.subtitle.text = "You're paired with The Reversion Archive."
    else
        m.subtitle.text = "Couldn't load your account right now."
    end if
end sub

sub onSignOut()
    ' Hand sign-out to MainScene (it wipes the token + returns to Pairing). §10.5
    m.top.signedOut = true
end sub
