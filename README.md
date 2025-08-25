# SimWishlist - WoW DPS Upgrade Addon

A comprehensive World of Warcraft addon that enhances item tooltips with DPS upgrade information from simulation data. Works with **any Droptimizer content** - dungeons, raids, or mixed scenarios.

## What It Does

- **Tooltip Enhancement**: Shows DPS upgrade values directly on item tooltips
- **Multi-Profile Support**: Import and manage multiple simulation profiles
- **Universal Content**: Works with dungeons, raids, and any Droptimizer content
- **Smart Import**: Automatic profile naming prevents data loss
- **Visual Organization**: Browse items by profile and source in an organized UI

## Quick Start

### 1. Run Your Simulation
- Go to [Raidbots](https://www.raidbots.com)
- Run **Droptimizer** on any content (dungeons, raids, mixed)
- Under "Simulation Details" → "Raw Files" → download `data.json`

### 2. Convert Your Data
- Visit the [SimWishlist Converter](https://imperial64.github.io/simwishlist)
- Upload your `data.json` file or paste the JSON text
- Customize the spec label if desired
- Click **"Convert to SIMWISH"**
- Click **"Copy Output"**

### 3. Import In-Game
- Install the addon from the latest release
- Type `/simwish` in-game
- Click **"Import"**
- Paste your SIMWISH text
- Click **"Import SIMWISH Text"**

### 4. Enjoy Enhanced Tooltips!
- Hover over items to see DPS upgrade information
- Use `/simwish show` to browse your upgrade lists
- Import more profiles without losing existing data

## Features

### Tooltip Enhancements
```
[Item Tooltip]
...existing item info...

SIMWISH
Dungeon Profile - +156.2 dps (+2.3%)
Raid Profile - +89.4 dps (+1.7%)
```

## 🔧 Commands

| Command | Action |
|---------|--------|
| `/simwish` | Open main menu |
| `/simwish import` | Open import panel |
| `/simwish show` | View your upgrade lists |
| `/simwish options` | Open settings panel |
| `/simwish help` | Show usage instructions |
| `/simwish clear` | Clear all profiles |
| `/simwish debug` | Show profile status |

## Options

Access via `/simwish options`:

- **Welcome Message**: Toggle login greeting on/off
- **Tooltip Enhancements**: Enable/disable DPS info on tooltips

Settings are saved per character.

### For Regular Updates
- Re-import simulations as gear changes
- Each import creates a new profile automatically
- Old data is preserved for comparison
- Tooltips show the best upgrades across all profiles

## File Structure

```
SimWishlist/
├── SimWishlist.lua    # Main addon logic
└── SimWishlist.toc    # Addon metadata
```

## Troubleshooting

### Empty Tooltip Enhancement
- Check `/simwish options` → Enable tooltip enhancements
- Verify you have imported profile data
- Use `/simwish debug` to check profile status

### Import Issues
- Ensure you're using Droptimizer data from Raidbots
- Check that the SIMWISH header format is correct
- Try `/simwish debug` to see import progress

### Missing Items
- Verify the simulation included the items you're looking for
- Check `/simwish show` to see what was actually imported
- Re-run simulation if items are missing from Droptimizer results

## Changelog

### Latest Updates
- **Universal Content Support**: Dungeons, raids, mixed content
- **Smart Profile System**: Automatic naming prevents data loss
- **Enhanced Tooltips**: Multi-profile display with clear formatting
- **Options Panel**: Quality of life customization settings
- **Streamlined Converter**: Simplified web interface

## Links & Support

- **GitHub Repository**: [https://github.com/imperial64/simwishlist](https://github.com/imperial64/simwishlist)
- **Web Converter**: [https://imperial64.github.io/simwishlist](https://imperial64.github.io/simwishlist)
- **Support Development**: [https://www.patreon.com/c/imperial64](https://www.patreon.com/c/imperial64)
- **Issues & Bug Reports**: [GitHub Issues](https://github.com/imperial64/simwishlist/issues)

## Contributing

This is an open source project! Feedback, suggestions, and contributions are welcome through GitHub issues and pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

*If you find this addon helpful, consider supporting development on [Patreon](https://www.patreon.com/c/imperial64)!*