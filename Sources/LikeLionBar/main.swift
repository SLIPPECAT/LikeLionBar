import AppKit

// 창을 만들기 전에 확인해야 메뉴바에 아이콘이 두 개 스치는 일이 없다.
if SingleInstance.anotherIsRunning() {
    exit(0)
}

let app = NSApplication.shared

// .accessory: Dock에 안 뜨고 메뉴바에만 상주한다. Info.plist의 LSUIElement와 짝.
app.setActivationPolicy(.accessory)

// 전역으로 잡아둬야 delegate가 해제되지 않는다.
let delegate = AppDelegate()
app.delegate = delegate

app.run()
