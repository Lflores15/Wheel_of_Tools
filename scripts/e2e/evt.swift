import Foundation
import CoreGraphics
// evt move x y | down x y | drag x y | up x y | shift down|up | ctrl down|up | loc
let a = CommandLine.arguments
let src = CGEventSource(stateID: .hidSystemState)
func mouse(_ type: CGEventType, _ x: Double, _ y: Double, flags: CGEventFlags = []) {
    let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    e.flags = flags
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    e.post(tap: .cghidEventTap)
}
func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
    e.type = .flagsChanged
    e.flags = flags
    e.post(tap: .cghidEventTap)
}
let flagArg = a.count > 4 ? a[4] : ""
let fl: CGEventFlags = flagArg == "shift" ? .maskShift : (flagArg == "ctrl" ? .maskControl : [])
switch a[1] {
case "move": mouse(.mouseMoved, Double(a[2])!, Double(a[3])!, flags: fl)
case "down": mouse(.leftMouseDown, Double(a[2])!, Double(a[3])!, flags: fl)
case "drag": mouse(.leftMouseDragged, Double(a[2])!, Double(a[3])!, flags: fl)
case "up": mouse(.leftMouseUp, Double(a[2])!, Double(a[3])!, flags: fl)
case "shift": key(56, down: a[2] == "down", flags: a[2] == "down" ? .maskShift : [])
case "ctrl": key(59, down: a[2] == "down", flags: a[2] == "down" ? .maskControl : [])
case "loc": let p = CGEvent(source: nil)!.location; print(Int(p.x), Int(p.y))
default: break
}
