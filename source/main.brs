' Reversion TV — Roku port
' Entry point. Spins up the SceneGraph screen and runs MainScene, which
' owns the auth gate (token -> Home, no token -> Pairing) per TV_APP_SPEC §2.

sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.show()

    ' Forward launch args (e.g. deep links) to the scene for later use.
    if args <> invalid then
        scene.launchArgs = args
    end if

    while true
        msg = wait(0, port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent" then
            if msg.isScreenClosed() then return
        end if
    end while
end sub
