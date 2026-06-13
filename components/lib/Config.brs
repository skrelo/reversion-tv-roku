' Global config / constants. TV_APP_SPEC §2, §4, §11.
' Backend is ALWAYS production https://reversion.app.

function ReversionConfig() as object
    return {
        BASE_URL: "https://reversion.app"
        API_PREFIX: "/api/mobile"

        ' roRegistry section name (token + prefs live here). §11
        REGISTRY_SECTION: "reversion_tv"

        ' Prefs keys (mirror Tizen player.* naming where it helps parity). §11
        KEY_AUTH_TOKEN: "auth_token"
        KEY_PLAYBACK_SPEED: "player.defaultSpeed"
        KEY_AUTOPLAY_NEXT: "player.autoplayNext"
        KEY_ANNOTATION_POPUPS: "player.annotationPopups"
        KEY_NOTE_POPUPS: "player.notePopups"

        ' Network retry (§2): up to 3x on transient failures with backoff.
        RETRY_MAX: 3
        RETRY_BACKOFF_MS: [300, 800, 1500]
        HTTP_TIMEOUT_MS: 30000
    }
end function

' Device name reported to the pairing endpoint (§5). Roku exposes brand/model
' via roDeviceInfo; produce something like "Roku Ultra" / "Roku TV".
function ReversionDeviceName() as string
    di = CreateObject("roDeviceInfo")
    model = di.GetModelDisplayName()
    if model = invalid or model = "" then model = "Roku"

    ' Append a stable per-device id. The backend dedups Sanctum tokens BY NAME
    ' (deletes existing tokens with the same name on each sign-in), so a bare
    ' model name ("Roku Ultra") makes every Roku Ultra share one token slot — a
    ' sign-in on one device then revokes the token another device is holding,
    ' signing it out. That breaks Roku's cloud cert, which runs on a pool of
    ' devices sharing the one reviewer account. GetChannelClientId is a stable
    ' per-channel-per-device UUID, so each physical Roku gets its own token slot
    ' while a re-sign-in on the SAME device still dedups cleanly.
    uid = di.GetChannelClientId()
    if uid = invalid or uid = "" then return model
    return model + " " + Right(uid, 12)
end function

' ── TEMPORARY cert diagnostic ──────────────────────────────────────────
' Fire-and-forget remote beacon to the backend debug sink (mirrored to Slack).
' MainScene seeds m.global.debugTask on boot; this no-ops until then and never
' blocks (the DebugTask thread does the actual POST). `data` is optional.
' Remove this + DebugTask + the backend /tv-debug route before final cert.
sub LogBeacon(event as string, screen as string, data as object)
    g = m.global
    if g = invalid then return
    t = g.debugTask
    if t = invalid then return
    payload = { event: event, screen: screen, device: ReversionDeviceName() }
    if data <> invalid then payload.data = data
    ' Append to the queue (read-modify-write). All UI components share the render
    ' thread, so there's a single writer — no lost appends. DebugTask drains by
    ' index, so cold-start beacons set before its observer is live aren't lost.
    q = t.beacon
    if q = invalid then q = []
    q.push(payload)
    t.beacon = q
end sub
