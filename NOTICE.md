# Third-Party Notices

The MIT License in this repository applies to the project source code unless a file states otherwise. It does not grant rights to third-party names, marks, logos, photographs, or data.

## HLTV

Match information is read from publicly rendered pages on [HLTV.org](https://www.hltv.org/). HLTV is not affiliated with, sponsoring, or endorsing this project. Use of HLTV content and access to its website remain subject to HLTV's terms and policies.

## Team Logos and Trademarks

Files in these directories are derived from team-logo resources rendered by HLTV:

- `Resources/OriginalTeamLogos/`
- `Resources/DarkTeamLogos/`

The current snapshot covers the top 100 teams in the [HLTV Valve global ranking for October 28, 2026](https://www.hltv.org/valve-ranking/teams/2026/october/28). Per-team ranks, source URLs, filenames, and placeholder status are recorded in `docs/team-logos.json`. Original PNG/SVG resources retain their source artwork; dark variants are generated with `scripts/generate-dark-team-logos.swift` using its existing dark-neutral and color thresholds. Color, ex-Zero Tenacity, and ex-RUSTEC use the letter placeholders provided by HLTV.

Team names, logos, and related trademarks belong to their respective owners. The dark variants are accessibility-oriented transformations for display on a dark background. These assets are excluded from the MIT License.

## Application Artwork

The following user-supplied artwork is excluded from the MIT License unless the applicable rightsholder grants separate permission:

- `Resources/AppIcon.icns`
- `Resources/HeaderIcon@2x.jpg`
- `Resources/MenuBarIcon@2x.png`

Downstream distributors are responsible for confirming that they have the rights needed to redistribute or replace these assets.

## Counter-Strike and Valve

Counter-Strike and Valve are trademarks or registered trademarks of Valve Corporation. This project is an unofficial community tool and is not affiliated with Valve Corporation.
