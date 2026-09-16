# MeetingNotes

Een privacyvriendelijke macOS-app voor Nederlandse vergadertranscriptie, sprekerherkenning en samenvattingen.

## Updates

De app heeft een ingebouwde updatecontrole. De releasefeed is een klein publiek JSON-bestand met deze vorm:

```json
{
  "version": "0.3.0",
  "build": 3,
  "downloadURL": "https://example.com/MeetingNotes-0.3.0.dmg",
  "notes": "Verbeterde transcriptie en nieuwe functies."
}
```

De feed-URL staat in `packaging/Info.plist` onder `MNUpdateFeedURL`. Zodra de GitHub-repository en release-hosting klaar zijn, vullen we daar de echte URL in. Updates worden bewust gedownload en geïnstalleerd; de app vervangt zichzelf niet stilletjes.

## Ontwerpdoelen

- Werkt onafhankelijk van Google Meet, Teams, Zoom en Discord.
- Neemt microfoon en systeemaudio als afzonderlijke kanalen op.
- Verwerkt audio lokaal waar mogelijk.
- Heeft een duidelijke opslaglocatie en volledige opruimfunctie.
- Bewaart per vergadering audio, JSON-transcriptie en leesbare Markdown-notulen.
- Geen verplichte installatie van Ollama, Homebrew, Python of Node.js voor eindgebruikers.
- Modulair opgebouwd zodat opname, transcriptie, sprekerherkenning en samenvatting afzonderlijk kunnen evolueren.

## Status

De huidige release is versie 0.3.0 en bevat de native macOS-shell, opslagbeheer, Finder-link, toestemming-flow, opname, lokale transcriptie, diarization, speaker-namen en een vergaderingen-overzicht.

## Bouwen

```bash
swift build
swift run MeetingNotes
```

## Lokale app-build

Maak een normale macOS-appbundle zonder Terminal-afhankelijkheid:

```bash
zsh scripts/package.sh
open dist/MeetingNotes.app
```

Voor distributie aan anderen gebruiken we Developer ID signing, notarization en een DMG. De appbundle gebruikt voorlopig een placeholder bundle identifier; die moet vóór publieke distributie nog naar een unieke identifier worden gewijzigd.

### Signed release

De volledige releaseflow staat in `scripts/release.sh`. Hiervoor is een Developer ID Application-certificaat nodig. De certificaatnaam kan als environment variable worden meegegeven:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Jouw Naam (TEAMID)"
zsh scripts/release.sh
```

Voor notarization moet eerst een `notarytool`-keychainprofiel worden aangemaakt. Daarna:

```bash
export NOTARY_KEYCHAIN_PROFILE="meetingnotes-notary"
zsh scripts/release.sh
```

Zonder certificaat blijft `scripts/package.sh` beschikbaar voor lokale testbuilds. Die build is niet bedoeld om zonder Gatekeeper-waarschuwing met anderen te delen.

Open het project eventueel met Xcode via `Package.swift`. Een volgende distributiestap is het toevoegen van Sparkle met een private update-signing key en een publieke appcast. Die sleutel komt niet in de repository.

## Licentie

Nog te bepalen. Voor een portfolio/open-source release wordt waarschijnlijk MIT gebruikt, met afzonderlijke third-party notices voor gebruikte libraries en modellen.
