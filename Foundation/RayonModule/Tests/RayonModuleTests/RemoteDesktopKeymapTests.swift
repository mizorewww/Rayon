//
//  RemoteDesktopKeymapTests.swift
//  RayonModuleTests
//
//  What an iPad's keys send: the Carbon keycode a Mac UU host takes, the
//  Windows virtual key a Windows UU host takes, and the KeySym a VNC host
//  takes.
//

@testable import RayonModule
import XCTest

final class RemoteDesktopKeymapTests: XCTestCase {
    private func stroke(_ usage: Int, _ characters: String = "") -> RemoteDesktopKeyStroke? {
        RemoteDesktopKeymap.stroke(hidUsage: usage, typing: characters, isDown: true)
    }

    private func windowsKey(_ stroke: RemoteDesktopKeyStroke?) -> Int32? {
        stroke.flatMap { RemoteDesktopKeymap.windowsVKForCarbon[$0.keyCode] }
    }

    /// UIKit names the arrows instead of typing them: the key is still the
    /// arrow, on every host.
    func testSpecialKeysAreKeysNotText() throws {
        let left = try XCTUnwrap(stroke(0x50, "UIKeyInputLeftArrow"))
        XCTAssertEqual(left.keyCode, 123)
        XCTAssertEqual(left.keySym, 0xFF51)
        XCTAssertEqual(windowsKey(left), 0x25)

        let escape = try XCTUnwrap(stroke(0x29, "UIKeyInputEscape"))
        XCTAssertEqual(escape.keyCode, 53)
        XCTAssertEqual(escape.keySym, 0xFF1B)
        XCTAssertEqual(windowsKey(escape), 0x1B)

        let f5 = try XCTUnwrap(stroke(0x3E, "UIKeyInputF5"))
        XCTAssertEqual(f5.keyCode, 96)
        XCTAssertEqual(f5.keySym, 0xFFC2)
        XCTAssertEqual(windowsKey(f5), 0x74)

        let pageDown = try XCTUnwrap(stroke(0x4E, "UIKeyInputPageDown"))
        XCTAssertEqual(pageDown.keySym, 0xFF56)
        XCTAssertEqual(windowsKey(pageDown), 0x22)

        let backspace = try XCTUnwrap(stroke(0x2A, "\u{8}"))
        XCTAssertEqual(backspace.keySym, 0xFF08)
        XCTAssertEqual(windowsKey(backspace), 0x08)
    }

    /// Ctrl+C: Control down, then C as the letter it is.
    func testCombinationIsModifierAndLetter() throws {
        let control = try XCTUnwrap(stroke(0xE0))
        XCTAssertEqual(control.keyCode, 59)
        XCTAssertEqual(control.keySym, 0xFFE3)
        XCTAssertEqual(windowsKey(control), 0xA2)

        let c = try XCTUnwrap(stroke(0x06, "c"))
        XCTAssertEqual(c.keyCode, 8)
        XCTAssertEqual(c.keySym, 0x63)
        XCTAssertEqual(windowsKey(c), 0x43)

        let command = try XCTUnwrap(stroke(0xE3))
        XCTAssertEqual(command.keySym, 0xFFEB)
        XCTAssertEqual(windowsKey(command), 0x5B)
    }

    /// A key outside the table sends nothing as a key: it is typed as text
    /// or not at all, never as a HID usage posing as a keycode.
    func testUnknownKeyHasNoStroke() {
        XCTAssertNil(stroke(0x90, "a"))
    }

    /// Every key the table knows has a Windows virtual key too.
    func testEveryKeyHasAWindowsKey() {
        for (usage, keyCode) in RemoteDesktopKeymap.carbonForHID {
            XCTAssertNotNil(RemoteDesktopKeymap.windowsVKForCarbon[keyCode], "HID 0x\(String(usage, radix: 16))")
        }
    }
}
