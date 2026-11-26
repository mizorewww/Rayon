/// Syntax colours shared by both editors, as sRGB hex values for light and
/// dark mode: muted enough for long reading, distinct in both modes.
enum EditorPalette {
    struct Swatch {
        let light: UInt32
        let dark: UInt32
    }

    static let keyword = Swatch(light: 0x9B2393, dark: 0xFC5FA3)
    static let string = Swatch(light: 0xC41A16, dark: 0xFC6A5D)
    static let number = Swatch(light: 0x1C00CF, dark: 0xD0BF69)
    static let comment = Swatch(light: 0x5D6C79, dark: 0x7F8C98)
    static let type = Swatch(light: 0x0B4F79, dark: 0x5DD8FF)
    static let function = Swatch(light: 0x326D74, dark: 0x67B7A4)
    static let property = Swatch(light: 0x3E8087, dark: 0x9EF1DD)
    static let constant = Swatch(light: 0x6C36A9, dark: 0xD0A8FF)
}

extension EditorPalette.Swatch {
    /// The red, green and blue components of one mode's colour, from 0 to 1.
    func components(dark isDark: Bool) -> (red: Double, green: Double, blue: Double) {
        let value = isDark ? dark : light
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
