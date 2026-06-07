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
    if model = invalid or model = "" then
        return "Roku"
    end if
    ' GetModelDisplayName already reads like "Roku Ultra" / "TCL Roku TV".
    return model
end function
