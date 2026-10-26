/*
 * C&C Generals PS5 - D3D8 smoke test.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Proves the graphics stack the game uses, on the console, before the game:
 * SDL3 (PS5 drivers) -> DXVK D3D8 -> RADV -> VK_KHR_display. It draws with
 * D3D8's fixed-function pipeline (pre-transformed, vertex-coloured triangles,
 * as Generals' 2D and UI drawing does) and reads the DualSense, a USB mouse
 * and a USB keyboard. Everything it learns goes to klog.
 *
 *   left stick: move the triangle   CROSS: change its colour
 *   mouse: moves the white square   OPTIONS or Esc: quit
 */
#include <SDL3/SDL.h>
#include <d3d8.h>

#include <cmath>

#include "ps5_title.h"

extern "C" IDirect3D8 *WINAPI Direct3DCreate8(UINT SDKVersion);

namespace {

constexpr int kWidth = 1920;
constexpr int kHeight = 1080;
constexpr DWORD kVertexFormat = D3DFVF_XYZRHW | D3DFVF_DIFFUSE;

struct Vertex {
    float x, y, z, rhw;
    DWORD color;
};

DWORD Hue(float t)
{
    auto channel = [t](float offset) {
        return static_cast<DWORD>(127.5f + 127.5f * std::sin(t + offset));
    };
    return D3DCOLOR_XRGB(channel(0.0f), channel(2.094f), channel(4.189f));
}

void Quad(IDirect3DDevice8 *device, float x, float y, float size, DWORD color)
{
    const Vertex v[4] = {
        { x, y, 0.5f, 1.0f, color },
        { x + size, y, 0.5f, 1.0f, color },
        { x, y + size, 0.5f, 1.0f, color },
        { x + size, y + size, 0.5f, 1.0f, color },
    };
    device->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, sizeof(Vertex));
}

} // namespace

int main(int, char **)
{
    ps5_title_init("D3D8 Test");

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD)) {
        ps5_say("SDL_Init failed: %s", SDL_GetError());
        return 1;
    }
    ps5_say("SDL %d video driver: %s", SDL_GetVersion(), SDL_GetCurrentVideoDriver());

    SDL_Window *window = SDL_CreateWindow("D3D8 Test", kWidth, kHeight, SDL_WINDOW_VULKAN);
    if (!window) {
        ps5_say("SDL_CreateWindow failed: %s", SDL_GetError());
        return 1;
    }

    IDirect3D8 *d3d = Direct3DCreate8(D3D_SDK_VERSION);
    if (!d3d) {
        ps5_say("Direct3DCreate8 failed");
        return 1;
    }
    D3DADAPTER_IDENTIFIER8 adapter = {};
    if (SUCCEEDED(d3d->GetAdapterIdentifier(D3DADAPTER_DEFAULT, 0, &adapter))) {
        ps5_say("adapter: %s (vendor 0x%04x device 0x%04x)", adapter.Description,
                (unsigned)adapter.VendorId, (unsigned)adapter.DeviceId);
    }

    D3DPRESENT_PARAMETERS pp = {};
    pp.BackBufferWidth = kWidth;
    pp.BackBufferHeight = kHeight;
    pp.BackBufferFormat = D3DFMT_X8R8G8B8;
    pp.BackBufferCount = 1;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.hDeviceWindow = reinterpret_cast<HWND>(window);
    pp.Windowed = TRUE;
    pp.EnableAutoDepthStencil = TRUE;
    pp.AutoDepthStencilFormat = D3DFMT_D24S8;

    IDirect3DDevice8 *device = nullptr;
    HRESULT hr = d3d->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, pp.hDeviceWindow,
                                   D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &device);
    if (FAILED(hr) || !device) {
        ps5_say("CreateDevice failed: 0x%08x", (unsigned)hr);
        return 1;
    }
    ps5_say("device created: %dx%d", kWidth, kHeight);

    device->SetVertexShader(kVertexFormat);
    device->SetRenderState(D3DRS_LIGHTING, FALSE);
    device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
    device->SetRenderState(D3DRS_ZENABLE, FALSE);

    SDL_Gamepad *gamepad = nullptr;
    float tri_x = kWidth * 0.5f;
    float tri_y = kHeight * 0.5f;
    int palette = 0;
    bool running = true;
    bool mouse_seen = false;
    bool key_seen = false;
    Uint64 frames = 0;
    Uint64 report_at = SDL_GetTicks() + 5000;
    Uint64 report_frames = 0;
    const Uint64 start = SDL_GetTicks();

    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
            case SDL_EVENT_GAMEPAD_ADDED:
                if (!gamepad) {
                    gamepad = SDL_OpenGamepad(event.gdevice.which);
                    ps5_say("gamepad: %s (type %d)", SDL_GetGamepadName(gamepad), (int)SDL_GetGamepadType(gamepad));
                    SDL_SetGamepadLED(gamepad, 255, 140, 0);
                }
                break;
            case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
                if (event.gbutton.button == SDL_GAMEPAD_BUTTON_START) {
                    running = false;
                } else if (event.gbutton.button == SDL_GAMEPAD_BUTTON_SOUTH) {
                    palette++;
                    SDL_RumbleGamepad(gamepad, 0x8000, 0x8000, 120);
                }
                ps5_say("gamepad button %d", event.gbutton.button);
                break;
            case SDL_EVENT_MOUSE_MOTION:
                if (!mouse_seen) {
                    mouse_seen = true;
                    ps5_say("mouse: first motion");
                }
                break;
            case SDL_EVENT_MOUSE_BUTTON_DOWN:
                ps5_say("mouse button %d at %.0f,%.0f", event.button.button, event.button.x, event.button.y);
                break;
            case SDL_EVENT_KEY_DOWN:
                if (!key_seen) {
                    key_seen = true;
                    ps5_say("keyboard: first key");
                }
                ps5_say("key %s", SDL_GetScancodeName(event.key.scancode));
                if (event.key.scancode == SDL_SCANCODE_ESCAPE) {
                    running = false;
                }
                break;
            case SDL_EVENT_QUIT:
                running = false;
                break;
            default:
                break;
            }
        }

        if (gamepad) {
            const float lx = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_LEFTX) / 32767.0f;
            const float ly = SDL_GetGamepadAxis(gamepad, SDL_GAMEPAD_AXIS_LEFTY) / 32767.0f;
            tri_x = SDL_clamp(tri_x + (std::fabs(lx) > 0.15f ? lx * 12.0f : 0.0f), 0.0f, (float)kWidth);
            tri_y = SDL_clamp(tri_y + (std::fabs(ly) > 0.15f ? ly * 12.0f : 0.0f), 0.0f, (float)kHeight);
        }

        const float t = (SDL_GetTicks() - start) / 1000.0f;
        device->Clear(0, nullptr, D3DCLEAR_TARGET, Hue(t * 0.3f) & 0x003f3f3f, 1.0f, 0);
        if (SUCCEEDED(device->BeginScene())) {
            const DWORD colors[3][3] = {
                { D3DCOLOR_XRGB(255, 60, 60), D3DCOLOR_XRGB(60, 255, 60), D3DCOLOR_XRGB(60, 60, 255) },
                { D3DCOLOR_XRGB(255, 200, 0), D3DCOLOR_XRGB(255, 80, 0), D3DCOLOR_XRGB(120, 40, 0) },
                { D3DCOLOR_XRGB(255, 255, 255), D3DCOLOR_XRGB(128, 128, 128), D3DCOLOR_XRGB(32, 32, 32) },
            };
            const DWORD *c = colors[palette % 3];
            const float r = 220.0f;
            Vertex tri[3];
            for (int i = 0; i < 3; i++) {
                const float a = t + i * 2.0944f;
                tri[i] = { tri_x + r * std::cos(a), tri_y + r * std::sin(a), 0.5f, 1.0f, c[i] };
            }
            device->DrawPrimitiveUP(D3DPT_TRIANGLELIST, 1, tri, sizeof(Vertex));

            float mx = 0.0f, my = 0.0f;
            SDL_GetMouseState(&mx, &my);
            Quad(device, mx - 8.0f, my - 8.0f, 16.0f, D3DCOLOR_XRGB(255, 255, 255));
            device->EndScene();
        }
        hr = device->Present(nullptr, nullptr, nullptr, nullptr);
        if (FAILED(hr)) {
            ps5_say("Present failed: 0x%08x", (unsigned)hr);
            break;
        }
        if (frames++ == 0) {
            ps5_say("first frame presented");
        }
        if (SDL_GetTicks() >= report_at) {
            ps5_say("%.1f fps", (frames - report_frames) / 5.0);
            report_frames = frames;
            report_at += 5000;
        }
    }

    ps5_say("quitting after %llu frames", (unsigned long long)frames);
    device->Release();
    d3d->Release();
    if (gamepad) {
        SDL_CloseGamepad(gamepad);
    }
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
