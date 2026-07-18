from __future__ import annotations

import base64
import json

from sanic import Blueprint, Request
from sanic.log import logger
from sanic.response import html

from auth.clerk_client import ClerkAuthError, user_payload_from_session
from auth.dependencies import handoff_principal
from common.responses import fail, ok
from users.routes import account_type_from_body


bp_auth_web = Blueprint("auth_web")


def _clerk_frontend_api(publishable_key: str) -> str:
    try:
        encoded = publishable_key.split("_")[2]
        padding = "=" * (-len(encoded) % 4)
        decoded = base64.b64decode(encoded + padding).decode("utf-8")
        return decoded.rstrip("$").strip()
    except Exception:
        return ""


def _auth_page(publishable_key: str) -> str:
    frontend_api = _clerk_frontend_api(publishable_key)
    cfg = json.dumps({"publishableKey": publishable_key, "frontendApi": frontend_api})
    ui_src = f"https://{frontend_api}/npm/@clerk/ui@1/dist/ui.browser.js" if frontend_api else "https://cdn.jsdelivr.net/npm/@clerk/ui@1/dist/ui.browser.js"
    clerk_src = f"https://{frontend_api}/npm/@clerk/clerk-js@6/dist/clerk.browser.js" if frontend_api else "https://cdn.jsdelivr.net/npm/@clerk/clerk-js@6/dist/clerk.browser.js"
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Neuralese Login</title>
  <script defer crossorigin="anonymous" src="{ui_src}" type="text/javascript"></script>
  <script defer crossorigin="anonymous" data-clerk-publishable-key="{publishable_key}" src="{clerk_src}" type="text/javascript"></script>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; min-height: 100vh; display: grid; place-items: center; background: #09090b; color: #fafafa; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    main {{ width: min(92vw, 560px); border: 1px solid #27272a; border-radius: 10px; background: #18181b; padding: 30px; box-shadow: 0 24px 80px rgba(0,0,0,.35); }}
    h1 {{ margin: 6px 0 0; font-size: 32px; line-height: 1.1; }}
    .eyebrow {{ margin: 0; color: #67e8f9; font-size: 13px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }}
    .panel {{ margin-top: 22px; border: 1px solid #27272a; border-radius: 8px; background: #09090b; padding: 18px; }}
    .muted {{ color: #a1a1aa; line-height: 1.55; }}
    .mono {{ color: #a1a1aa; font: 13px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; overflow-wrap: anywhere; }}
    input[type=text] {{ width: 100%; margin-top: 12px; border: 1px solid #3f3f46; border-radius: 8px; background: #18181b; color: white; padding: 12px; font-size: 16px; }}
    fieldset {{ margin: 18px 0 0; padding: 0; border: 0; }}
    .choices {{ display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 10px; }}
    label.choice {{ display: flex; align-items: center; gap: 8px; border: 1px solid #3f3f46; border-radius: 8px; background: #18181b; padding: 12px; cursor: pointer; }}
    button {{ border: 0; border-radius: 8px; background: #67e8f9; color: #09090b; padding: 12px 14px; font-weight: 800; cursor: pointer; }}
    button.secondary {{ background: #27272a; color: #fafafa; }}
    button:disabled {{ opacity: .55; cursor: wait; }}
    .row {{ display: flex; gap: 10px; align-items: center; justify-content: space-between; flex-wrap: wrap; }}
    .error {{ color: #fca5a5; }}
    .ok {{ color: #86efac; }}
    #clerk-root {{ margin-top: 22px; }}
  </style>
</head>
<body>
  <main>
    <div class="row">
      <div>
        <p class="eyebrow">Neuralese</p>
        <h1>Account login</h1>
      </div>
      <button id="sign-out" class="secondary" hidden>Sign out</button>
    </div>
    <section id="status" class="panel muted">Loading Clerk...</section>
    <section id="profile" class="panel" hidden></section>
    <section id="clerk-root"></section>
  </main>
  <script>
    window.NEURALESE_AUTH = {cfg};
  </script>
  <script>
    const statusEl = document.getElementById("status");
    const profileEl = document.getElementById("profile");
    const clerkRoot = document.getElementById("clerk-root");
    const signOutButton = document.getElementById("sign-out");
    const url = new URL(window.location.href);
    const attemptId = url.searchParams.get("attempt_id") || localStorage.getItem("neuralese_attempt_id") || "";
    const mode = url.searchParams.get("mode") === "sign-up" ? "sign-up" : "sign-in";
    const fresh = url.searchParams.get("fresh") === "1";
    if (attemptId) localStorage.setItem("neuralese_attempt_id", attemptId);
    const authPath = "/auth" + (attemptId ? "?attempt_id=" + encodeURIComponent(attemptId) : "");

    function setStatus(text, cls = "muted") {{
      statusEl.className = "panel " + cls;
      statusEl.textContent = text;
    }}

    async function waitForClerk() {{
      for (let i = 0; i < 200; i++) {{
        if (window.Clerk && window.__internal_ClerkUICtor) return window.Clerk;
        await new Promise((resolve) => setTimeout(resolve, 50));
      }}
      throw new Error("Clerk failed to load.");
    }}

    async function clerkToken() {{
      const session = window.Clerk.session;
      if (!session) throw new Error("No active Clerk session.");
      const token = await session.getToken();
      if (!token) throw new Error("Could not get Clerk session token.");
      return token;
    }}

    async function postJson(path, body) {{
      const response = await fetch(path, {{
        method: "POST",
        headers: {{"Content-Type": "application/json"}},
        body: JSON.stringify(body || {{}})
      }});
      const data = await response.json().catch(() => ({{ok: false, error: "invalid response"}}));
      if (!response.ok || !data.ok) throw new Error(data.error || "Request failed.");
      return data;
    }}

    async function loadProfile() {{
      const token = await clerkToken();
      return await postJson("/auth/api/profile", {{session_token: token}});
    }}

    async function completeLogin() {{
      if (!attemptId) {{
        setStatus("Open this page from Neuralese to connect your app.");
        return;
      }}
      setStatus("Connecting your account to Neuralese...");
      const token = await clerkToken();
      await postJson("/auth/api/complete-login", {{session_token: token, attempt_id: attemptId}});
      localStorage.removeItem("neuralese_attempt_id");
      setStatus("You're signed in. Return to Neuralese.", "ok");
    }}

    function renderUsernameForm(profile) {{
      profileEl.hidden = false;
      profileEl.innerHTML = `
        <p><strong>Choose your Neuralese username</strong></p>
        <p class="muted">This unique username is what classmates and teachers will see.</p>
        <form id="username-form">
          <input id="username" type="text" minlength="3" maxlength="20" pattern="[A-Za-z0-9_]{{3,20}}" placeholder="username" value="${{profile.username || ""}}" required>
          <fieldset>
            <legend><strong>Are you a teacher?</strong></legend>
            <div class="choices">
              <label class="choice"><input type="radio" name="teacher" value="no" ${{profile.type !== "teacher" ? "checked" : ""}}> No</label>
              <label class="choice"><input type="radio" name="teacher" value="yes" ${{profile.type === "teacher" ? "checked" : ""}}> Yes</label>
            </div>
          </fieldset>
          <p id="form-message" class="error"></p>
          <button id="continue-button" type="submit">Continue</button>
        </form>
      `;
      document.getElementById("username-form").addEventListener("submit", async (event) => {{
        event.preventDefault();
        const button = document.getElementById("continue-button");
        const message = document.getElementById("form-message");
        button.disabled = true;
        message.textContent = "";
        try {{
          const token = await clerkToken();
          const username = document.getElementById("username").value;
          const teacher = document.querySelector("input[name=teacher]:checked").value === "yes";
          await postJson("/auth/api/claim-username", {{session_token: token, username, teacher}});
          profileEl.hidden = true;
          await completeLogin();
        }} catch (error) {{
          message.textContent = error.message || String(error);
        }} finally {{
          button.disabled = false;
        }}
      }});
    }}

    async function afterSignedIn() {{
      const user = window.Clerk.user;
      const display = user?.firstName || user?.username || user?.primaryEmailAddress?.emailAddress || "Neuralese user";
      signOutButton.hidden = false;
      setStatus(`Signed in as ${{display}}.`);
      const profileResponse = await loadProfile();
      if (profileResponse.needs_username === false && profileResponse.profile?.username) {{
        await completeLogin();
      }} else {{
        renderUsernameForm(profileResponse.profile || {{}});
      }}
    }}

    async function mountClerk() {{
      const clerk = await waitForClerk();
      await clerk.load({{ui: {{ClerkUI: window.__internal_ClerkUICtor}}}});
      signOutButton.addEventListener("click", async () => {{
        try {{
          if (attemptId) await postJson("/auth/api/sign-out", {{attempt_id: attemptId}});
        }} catch (error) {{}}
        if (attemptId) {{
          localStorage.setItem("neuralese_attempt_id", attemptId);
        }} else {{
          localStorage.removeItem("neuralese_attempt_id");
        }}
        await clerk.signOut();
        location.href = "/auth" + (attemptId ? "?attempt_id=" + encodeURIComponent(attemptId) : "");
      }});
      if (fresh && clerk.user && !sessionStorage.getItem("neuralese_fresh_" + attemptId)) {{
        sessionStorage.setItem("neuralese_fresh_" + attemptId, "1");
        await clerk.signOut();
        location.href = authPath;
        return;
      }}
      if (clerk.user) {{
        await afterSignedIn();
        return;
      }}
      setStatus("Sign in or create an account. After that, Neuralese will ask for a unique username.");
      const switchUrl = "/auth?" + new URLSearchParams({{...(attemptId ? {{attempt_id: attemptId}} : {{}}), mode: mode === "sign-in" ? "sign-up" : "sign-in"}}).toString();
      const redirectProps = {{
        routing: "hash",
        signInForceRedirectUrl: authPath,
        signInFallbackRedirectUrl: authPath,
        signUpForceRedirectUrl: authPath,
        signUpFallbackRedirectUrl: authPath,
        afterSignInUrl: authPath,
        afterSignUpUrl: authPath,
        redirectUrl: authPath
      }};
      if (mode === "sign-up") {{
        clerk.mountSignUp(clerkRoot, {{...redirectProps, signInUrl: switchUrl}});
      }} else {{
        clerk.mountSignIn(clerkRoot, {{...redirectProps, signUpUrl: switchUrl}});
      }}
    }}

    mountClerk().catch((error) => setStatus(error.message || String(error), "error"));
  </script>
</body>
</html>"""


@bp_auth_web.get("/auth")
async def auth_page(request: Request):
    return render_auth_page(request)


def render_auth_page(request: Request):
    key = request.app.ctx.settings.clerk_publishable_key
    if not key:
        return html("<body>Missing NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY.</body>", status=500)
    response = html(_auth_page(key))
    response.headers["Cache-Control"] = "no-store, max-age=0"
    return response


@bp_auth_web.post("/auth/api/profile")
async def auth_profile(request: Request):
    body = request.json or {}
    try:
        principal = handoff_principal(user_payload_from_session(request.app.ctx.settings, str(body.get("session_token", ""))))
        profile = request.app.ctx.user_service.get_or_create_from_principal(principal)
    except ClerkAuthError as exc:
        return fail(str(exc), 401)
    return ok({"profile": request.app.ctx.user_service.public_payload(profile), "needs_username": profile.username == ""})


@bp_auth_web.post("/auth/api/claim-username")
async def auth_claim_username(request: Request):
    body = request.json or {}
    try:
        principal = handoff_principal(user_payload_from_session(request.app.ctx.settings, str(body.get("session_token", ""))))
        logger.info("auth web claim username clerk_user_id=%s username=%s", principal.clerk_user_id, str(body.get("username", "")))
        profile = request.app.ctx.user_service.claim_username(principal, str(body.get("username", "")), account_type_from_body(body))
    except ClerkAuthError as exc:
        return fail(str(exc), 401)
    except ValueError as exc:
        return fail(str(exc), 400)
    return ok({"profile": request.app.ctx.user_service.public_payload(profile), "needs_username": False})


@bp_auth_web.post("/auth/api/complete-login")
async def auth_complete_login(request: Request):
    body = request.json or {}
    try:
        clerk_user = user_payload_from_session(request.app.ctx.settings, str(body.get("session_token", "")))
        logger.info("auth web complete attempt_id=%s clerk_user_id=%s", str(body.get("attempt_id", "")), clerk_user.get("clerk_user_id", ""))
        principal = handoff_principal(clerk_user)
        profile = request.app.ctx.user_service.get_or_create_from_principal(principal)
        attempt = request.app.ctx.auth_attempts.complete(
            str(body.get("attempt_id", "")),
            request.app.ctx.settings,
            clerk_user,
            profile,
            request.app.ctx.user_service.public_payload(profile),
        )
    except ClerkAuthError as exc:
        return fail(str(exc), 401)
    except ValueError as exc:
        return fail(str(exc), 409 if str(exc) == "username_required" else 400)
    return ok(request.app.ctx.auth_attempts.result_payload(attempt))


@bp_auth_web.post("/auth/api/sign-out")
async def auth_sign_out(request: Request):
    body = request.json or {}
    attempt_id = str(body.get("attempt_id", ""))
    try:
        attempt = request.app.ctx.auth_attempts.signed_out(attempt_id) if attempt_id else None
    except ValueError as exc:
        return fail(str(exc), 404)
    payload = request.app.ctx.auth_attempts.result_payload(attempt) if attempt else {"status": "signed_out"}
    return ok(payload)
