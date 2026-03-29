# Solitaire Slasher

A modern, mobile-optimized collection of classic card and puzzle games built with Godot 4. Featuring Solitaire, Sudoku, and Spider Solitaire with enhanced UI for iPhone and iPad devices.

## 🎮 Games Included

### 🃏 Classic Solitaire
- Traditional Klondike Solitaire gameplay
- Drag-and-drop card mechanics
- Auto-complete functionality
- Undo/Redo support
- Multiple difficulty levels

### 🧩 Sudoku
- Classic 9x9 Sudoku puzzles
- Multiple difficulty levels (Easy, Medium, Hard)
- Smart note-taking system
- Error checking and hints
- Mirror mode for advanced players

### 🕷️ Spider Solitaire
- One-suit Spider Solitaire
- Smooth card animations
- Strategic gameplay
- Win detection and celebration

## 📱 Mobile-Optimized Features

### iPhone & iPad Enhancements
- **Large, touch-friendly buttons** - Optimized for finger interaction
- **Professional typography** - Larger fonts for better readability
- **Face icons** - 200px emoji indicators for difficulty selection
- **Enhanced sliders** - Wider, easier-to-use difficulty controls
- **Safe area support** - Proper spacing around iPhone notches

### Responsive Design
- Automatic orientation handling (portrait mode on mobile)
- Adaptive UI scaling for different screen sizes
- Touch-optimized controls and gestures

## 🛠️ Technical Stack

- **Engine**: Godot 4.x
- **Language**: GDScript
- **Platforms**: iOS, Android, Desktop
- **Architecture**: Component-based with modular game systems

## 📁 Project Structure

```
solitaireslasher/
├── scripts/                    # Game logic and UI
│   ├── Main.gd                # Main menu and game management
│   ├── Board.gd               # Solitaire board logic
│   ├── Game.gd                # Core game systems
│   └── ...
├── scenes/                     # Scene files
│   ├── Main.tscn              # Main game scene
│   └── ...
├── addons/                     # Third-party plugins
│   ├── card-framework/        # Card game framework
│   ├── FontAwesome/           # Icon system
│   └── ...
├── assets/                     # Game assets
│   ├── cards/                 # Card images and sprites
│   ├── game icons/            # Game selection icons
│   └── ...
└── export/                     # Platform-specific exports
    ├── solitaireslasher.xcodeproj/  # iOS Xcode project
    └── ...
```

## 🚀 Setup Instructions

### Prerequisites
- **Godot 4.x** - Download from [godotengine.org](https://godotengine.org/)
- **iOS Development** (optional):
  - Xcode 14+
  - Apple Developer Account
  - iOS device or simulator

### Local Development Setup

1. **Clone the Repository**
   ```bash
   git clone https://github.com/nmaison88/solitaireSlasher.git
   cd solitaireslasher
   ```

2. **Pull Git LFS Files** (for large binaries)
   ```bash
   git lfs pull
   ```

3. **Open in Godot**
   - Launch Godot
   - Click "Import" and select the project folder
   - Open `scenes/Main.tscn` to start

### iOS Development Setup

1. **Export from Godot**
   - Open Project → Export
   - Add iOS preset
   - Configure signing and team ID
   - Export to `export/` directory

2. **Build with Xcode**
   ```bash
   cd export/solitaireslasher.xcodeproj
   xcodebuild -project solitaireslasher.xcodeproj -scheme solitaireslasher -destination 'platform=iOS Simulator,name=iPhone 17'
   ```

3. **Archive for App Store**
   ```bash
   xcodebuild archive -project solitaireslasher.xcodeproj -scheme solitaireslasher -destination generic/platform=iOS -archivePath build.xcarchive
   ```

## 🎯 Game Features

### Difficulty System
- **Easy**: Happy face emoji 😊
- **Medium**: Neutral face emoji 😐  
- **Hard**: Angry face emoji 😠
- Large 200px face icons for mobile visibility
- Smooth slider controls with haptic feedback

### Multiplayer Support
- Local multiplayer for Solitaire and Sudoku
- Host/Join game functionality
- Real-time synchronization
- Player status indicators

### Theme System
- Light and dark themes
- Automatic theme detection
- Customizable color schemes
- Professional UI design

## 🔧 Development Notes

### Mobile Optimization
The UI automatically adapts to mobile devices with:
- Larger touch targets (minimum 44px)
- Enhanced font sizes for readability
- Safe area handling for notched devices
- Landscape/portrait orientation support

### Git LFS Usage
Large binary files are tracked with Git LFS:
- `libgodot.a` libraries (iOS builds)
- Export frameworks and plugins
- Large asset files

### Export Configuration
- iOS: Xcode project with proper signing
- Android: Gradle build system
- Desktop: Standalone executables

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on multiple platforms
5. Submit a pull request

### Development Guidelines
- Follow Godot coding conventions
- Test on both mobile and desktop
- Maintain mobile-first design principles
- Document new features

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🐛 Bug Reports & Feature Requests

- **Issues**: Report bugs via GitHub Issues
- **Features**: Request features via GitHub Discussions
- **Support**: Contact development team

## 🔄 Version History

### v1.0.0 (Current)
- Three game modes: Solitaire, Sudoku, Spider
- Mobile-optimized UI with large touch targets
- Multiplayer support for Solitaire and Sudoku
- Professional theme system
- iOS export with proper signing

### Upcoming Features
- More Solitaire variants
- Achievement system
- Cloud save synchronization
- Additional puzzle games

## 📱 Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| iOS | ✅ Full Support | iPhone & iPad optimized |
| Android | ✅ Full Support | Touch-optimized UI |
| Windows | ✅ Full Support | Desktop controls |
| macOS | ✅ Full Support | Native integration |
| Linux | ✅ Full Support | Desktop controls |

## 🎨 UI/UX Design

### Design Principles
- **Mobile-first**: Designed for touch interaction
- **Accessibility**: Large fonts and clear contrast
- **Professional**: Clean, modern interface
- **Responsive**: Adapts to all screen sizes

### Key Features
- 200px emoji indicators for difficulty
- 500x120px buttons on mobile devices
- Enhanced typography (72px titles on mobile)
- Smooth animations and transitions

---

**Built with ❤️ using Godot 4**
