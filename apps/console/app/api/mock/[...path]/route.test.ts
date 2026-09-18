import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it } from "vitest";
import { GET, MOCK_UNKNOWN_PHONE, POST, resetMockState } from "./route";

const ctx = (path: string) => ({ params: Promise.resolve({ path: path.split("/") }) });

const post = (path: string, body: unknown) =>
  POST(
    new NextRequest(`http://localhost/api/mock/${path}`, {
      method: "POST",
      body: JSON.stringify(body),
      headers: { "content-type": "application/json" },
    }),
    ctx(path),
  );

describe("in-app mock API (keeps e2e in sync with apps/api shapes)", () => {
  beforeEach(() => resetMockState());

  it("send -> verify -> me happy path", async () => {
    const send = await post("v1/auth/otp/send", { phone: "+919876543210" });
    expect(send.status).toBe(202);
    const sent = await send.json();
    expect(sent).toMatchObject({ channel: "sms", expires_in: 300, resends_left: 3 });
    expect(sent.phone_masked).toBe("+91******3210");

    const verify = await post("v1/auth/otp/verify", { phone: "+919876543210", code: "123456" });
    expect(verify.status).toBe(200);
    const tokens = await verify.json();
    expect(tokens.token_type).toBe("Bearer");
    expect(tokens.user.role).toBe("owner");

    const me = await GET(
      new NextRequest("http://localhost/api/mock/v1/me", {
        headers: { authorization: `Bearer ${tokens.access_token}` },
      }),
      ctx("v1/me"),
    );
    expect(me.status).toBe(200);
    const refresh = await post("v1/auth/refresh", { refresh_token: tokens.refresh_token });
    expect(refresh.status).toBe(200);
  });

  it("wrong code five times locks the number (otp_locked) and blocks resends", async () => {
    await post("v1/auth/otp/send", { phone: "+919876543210" });
    for (let i = 4; i >= 1; i--) {
      const res = await post("v1/auth/otp/verify", { phone: "+919876543210", code: "000000" });
      expect(res.status).toBe(401);
      expect(await res.json()).toMatchObject({ code: "otp_invalid", attempts_left: i });
    }
    const locked = await post("v1/auth/otp/verify", { phone: "+919876543210", code: "000000" });
    expect(locked.status).toBe(423);
    expect(await locked.json()).toMatchObject({ code: "otp_locked", retry_after: 900 });
    const send = await post("v1/auth/otp/send", { phone: "+919876543210" });
    expect(send.status).toBe(423);
  });

  it("fourth resend within the window is rate limited", async () => {
    for (let i = 0; i < 4; i++) {
      const res = await post("v1/auth/otp/send", { phone: "+919876543211" });
      expect(res.status).toBe(202);
    }
    const res = await post("v1/auth/otp/send", { phone: "+919876543211" });
    expect(res.status).toBe(429);
    expect(await res.json()).toMatchObject({ code: "otp_rate_limited" });
  });

  it("validates phones, unknown numbers and unauthenticated /me", async () => {
    expect((await post("v1/auth/otp/send", { phone: "123" })).status).toBe(422);
    expect((await post("v1/auth/otp/send", { phone: MOCK_UNKNOWN_PHONE })).status).toBe(404);
    expect((await post("v1/auth/otp/verify", { phone: "+919000000000", code: "1" })).status).toBe(
      404,
    );
    const me = await GET(new NextRequest("http://localhost/api/mock/v1/me"), ctx("v1/me"));
    expect(me.status).toBe(401);
    expect((await post("v1/auth/logout", { refresh_token: "x" })).status).toBe(204);
  });
});
