import SwiftUI

/// Compose `ImageVector` stand-in: a Material icon mapped to the closest SF Symbol.
/// Port `Icons.Rounded.Pause` as `Icons.Rounded.Pause` and draw it with `Icon(...)`.
struct ImageVector: Hashable {
    let systemName: String
    init(_ systemName: String) { self.systemName = systemName }
}

/// Every Material icon the Android app uses, under its Compose name.
enum Icons {
    enum Rounded {
        static let Accessibility = ImageVector("accessibility")
        static let Adjust = ImageVector("smallcircle.filled.circle")
        static let AirplanemodeActive = ImageVector("airplane")
        static let AutoAwesome = ImageVector("sparkles")
        static let Autorenew = ImageVector("arrow.triangle.2.circlepath")
        static let Balance = ImageVector("scalemass.fill")
        static let Block = ImageVector("nosign")
        static let Bolt = ImageVector("bolt.fill")
        static let Casino = ImageVector("dice.fill")
        static let CheckCircle = ImageVector("checkmark.circle.fill")
        static let Circle = ImageVector("circle.fill")
        static let Contrast = ImageVector("circle.lefthalf.filled")
        static let DeleteSweep = ImageVector("trash.fill")
        static let Description = ImageVector("doc.text.fill")
        static let DragHandle = ImageVector("line.3.horizontal")
        static let Edit = ImageVector("pencil")
        static let Email = ImageVector("envelope.fill")
        static let EmojiEvents = ImageVector("trophy.fill")
        static let FastForward = ImageVector("forward.fill")
        static let Flag = ImageVector("flag.fill")
        static let FormatListNumbered = ImageVector("list.number")
        static let GridOn = ImageVector("square.grid.3x3.fill")
        static let GridView = ImageVector("square.grid.2x2.fill")
        static let Groups = ImageVector("person.3.fill")
        static let Handshake = ImageVector("hands.clap.fill")
        static let Hexagon = ImageVector("hexagon.fill")
        static let History = ImageVector("clock.arrow.circlepath")
        static let Home = ImageVector("house.fill")
        static let HourglassTop = ImageVector("hourglass.tophalf.filled")
        static let Info = ImageVector("info.circle.fill")
        static let LocalFireDepartment = ImageVector("flame.fill")
        static let Lock = ImageVector("lock.fill")
        static let Looks6 = ImageVector("6.square.fill")
        static let LooksOne = ImageVector("1.square.fill")
        static let Memory = ImageVector("cpu.fill")
        static let MilitaryTech = ImageVector("medal.fill")
        static let MusicNote = ImageVector("music.note")
        static let PanTool = ImageVector("hand.raised.fill")
        static let Pause = ImageVector("pause.fill")
        static let Person = ImageVector("person.fill")
        static let PlayArrow = ImageVector("play.fill")
        static let PlayCircle = ImageVector("play.circle.fill")
        static let PrivacyTip = ImageVector("lock.shield.fill")
        static let Refresh = ImageVector("arrow.clockwise")
        static let Replay = ImageVector("arrow.counterclockwise")
        static let RestartAlt = ImageVector("arrow.counterclockwise.circle.fill")
        static let Save = ImageVector("square.and.arrow.down.fill")
        static let Schedule = ImageVector("clock.fill")
        static let ScreenRotation = ImageVector("rotate.right.fill")
        static let Settings = ImageVector("gearshape.fill")
        static let Shield = ImageVector("shield.fill")
        static let SmartToy = ImageVector("cpu")
        static let Speed = ImageVector("speedometer")
        static let SportsScore = ImageVector("flag.checkered")
        static let Star = ImageVector("star.fill")
        static let Style = ImageVector("square.stack.3d.up.fill")
        static let SwapVert = ImageVector("arrow.up.arrow.down")
        static let Sync = ImageVector("arrow.triangle.2.circlepath")
        static let Timer = ImageVector("timer")
        static let TouchApp = ImageVector("hand.tap.fill")
        static let Tune = ImageVector("slider.horizontal.3")
        static let Vibration = ImageVector("iphone.radiowaves.left.and.right")
        static let VisibilityOff = ImageVector("eye.slash.fill")
        static let Warning = ImageVector("exclamationmark.triangle.fill")
        static let WarningAmber = ImageVector("exclamationmark.triangle")
        static let WifiOff = ImageVector("wifi.slash")
        static let WorkspacePremium = ImageVector("rosette")
    }

    enum AutoMirrored {
        enum Rounded {
            static let ArrowBack = ImageVector("chevron.backward")
            static let ArrowForward = ImageVector("arrow.forward")
            static let ExitToApp = ImageVector("rectangle.portrait.and.arrow.right")
            static let KeyboardArrowRight = ImageVector("chevron.forward")
            static let Logout = ImageVector("rectangle.portrait.and.arrow.right")
            static let Undo = ImageVector("arrow.uturn.backward")
            static let VolumeOff = ImageVector("speaker.slash.fill")
            static let VolumeUp = ImageVector("speaker.wave.2.fill")
        }
    }
}

/// Compose `Icon(imageVector, contentDescription, tint, Modifier.size(n.dp))`.
/// SF Symbols are drawn as text at ~78% of the box (semibold) so their optical size and weight match
/// Material's rounded 24-in-24 glyphs.
struct Icon: View {
    let icon: ImageVector
    let contentDescription: String?
    var tint: Color
    var size: CGFloat

    init(_ icon: ImageVector, _ contentDescription: String? = nil, tint: Color = Royal.Ivory, size: CGFloat = 24) {
        self.icon = icon
        self.contentDescription = contentDescription
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Image(systemName: icon.systemName)
            .font(.system(size: size * 0.78, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .accessibilityLabel(contentDescription ?? "")
            .accessibilityHidden(contentDescription == nil)
    }
}
