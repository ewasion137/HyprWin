#pragma once
#include <d2d1.h>
#include <dwrite.h>
#include <windows.h>
#include <string>


// High-performance Direct2D renderer for UI and borders
class Renderer {
public:
    Renderer();
    ~Renderer();
    bool init(HWND hwnd);
    void begin_draw();
    void end_draw();
    void draw_rect(float x, float y, float w, float h, float r, float g, float b, float a, float thickness);
    void fill_rect(float x, float y, float w, float h, float r, float g, float b, float a);
    void clear(float r, float g, float b, float a);
    
    // New hardware-accelerated text rendering function
    void draw_text(const std::string& text, float x, float y, float size, float r, float g, float b, float a, const std::string& fontName);

private:
    ID2D1Factory* factory;
    ID2D1HwndRenderTarget* target;
    ID2D1SolidColorBrush* brush;
    IDWriteFactory* writeFactory; // DirectWrite factory pointer
};