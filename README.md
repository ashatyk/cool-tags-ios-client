# iOS Metal Shader Playground (900×1200)

SwiftUI + MetalKit плейграунд: шейдер поверх обычной фотографии.  
Оба слоя фиксированы 900×1200 и автоматически масштабируются под экран устройства.

Проверяем, что можем портировать и запускать шейдеры из проекта:
- [cool-tags playground (web)](https://cool-tags-zai9.vercel.app/)
- [cool-tags репозиторий](https://github.com/ashatyk/cool-tags)

---

## Возможности
- MTKView с прозрачным фоном и премультиплированным альфа-блендингом
- Фото как фон (через SwiftUI `Image`)
- Шейдер Metal (`Shaders.metal`) со свечением/лучами вокруг полигона
- Загрузка текстуры точек полигона (RG/RGBA) через `MTKTextureLoader`

---

## Требования
- Xcode 15+
- iOS 16+
- Swift 5.9+
- Устройство или симулятор с поддержкой Metal

---

## Запуск
```bash
# открой проект и запускай на симуляторе/устройстве
open ShaderPlayground.xcodeproj
