# Berechtigungen

Alle Rechte werden **serverseitig** geprüft (`server/permissions.lua` +
`server/main.lua`-Dispatcher). Client-Checks steuern nur die Sichtbarkeit im UI.

## Quellen & Reihenfolge

1. **Job + Grade (kumulativ):** bevorzugt aus DB-Tabelle `mt_permissions`
   (per Panel/Tablet pflegbar). Ist dort nichts hinterlegt → Fallback auf
   `config/permissions.lua` (`Config.Perms.Grades`). Ein Grade erbt alle Rechte
   niedrigerer Grades.
2. **Einzel-Overrides je Charakter** (`mt_permission_overrides`): `allow=1` gewährt,
   `allow=0` entzieht – hat Vorrang vor der Basis.
3. **`admin.full`** impliziert **alle** Rechte.
4. **Sperre** (`mt_user_locks`, `locked=1`) blockiert jeglichen Tablet-Zugriff.

Nur Jobs aus `Config.Perms.AllowedJobs` können das Tablet überhaupt nutzen
(Ausnahme: der Versicherungs-NPC ist für alle Spieler offen).

## Alle Rechte-Schlüssel

| Recht | Erlaubt |
|-------|---------|
| `tablet.open` | Tablet öffnen (Bootstrap) |
| `patient.search` | Patienten suchen |
| `patient.view` | Patientenakten ansehen |
| `patient.edit` | Patientenakten bearbeiten |
| `treatment.create` | Behandlungen erstellen |
| `treatment.edit` | Behandlungen bearbeiten |
| `treatment.archive` | Behandlungen archivieren |
| `notes.internal.view` | Sensible interne Notizen ansehen/erstellen |
| `invoice.create` | Rechnungen erstellen |
| `invoice.cancel` | Rechnungen stornieren |
| `discount.grant` | Manuelle Rabatte vergeben |
| `pricelist.view` | Preisliste ansehen |
| `pricelist.edit` | Preisliste bearbeiten |
| `insurance.patient.view` | Versicherung eines Patienten ansehen |
| `insurance.manage` | Versicherungsstufen/-verträge verwalten |
| `insurance.failed.view` | Fehlgeschlagene Beiträge ansehen |
| `insurance.retry` | Abbuchungen manuell erneut ausführen |
| `staff.view` | Mitarbeiteraktivitäten ansehen |
| `audit.view` | Audit-Logs ansehen |
| `settings.edit` | Einstellungen/Branding/Rechte verändern |
| `admin.full` | Vollständiger Administratorzugriff (impliziert alles) |

## Rollen-Beispiel (Standard-Seed, frei anpassbar)

Definiert in `config/permissions.lua` → `Config.Perms.Grades.ambulance`:

| Grade | Rolle | Rechte (kumulativ) |
|------:|-------|--------------------|
| 0 | Praktikant | `tablet.open`, `patient.search`, `patient.view`, `pricelist.view`, `insurance.patient.view` |
| 1 | Rettungssanitäter | + `treatment.create`, `patient.edit` |
| 2 | Arzt | + `treatment.edit`, `treatment.archive`, `invoice.create`, `discount.grant`, `notes.internal.view` |
| 3 | Oberarzt | + `invoice.cancel`, `staff.view`, `audit.view`, `insurance.failed.view`, `insurance.retry` |
| 4 | Klinikleitung | + `admin.full` |

> Ränge stehen **nicht** fest im Code. Passe die Zuordnung in der Config an oder
> pflege sie in der DB-Tabelle `mt_permissions` (überschreibt die Config).

## Overrides & Sperren pflegen

Über die NUI-Callbacks (Recht `settings.edit`):

- `perms.setOverride` → `{ identifier, perm, allow }` – Einzelrecht gewähren/entziehen.
- `perms.lock` → `{ identifier, locked, reason }` – Charakter für das Tablet sperren.

Beide invalidieren den Rechte-Cache sofort und werden im Audit-Log protokolliert.

## Cache

Effektive Rechte werden pro Charakter 30 s gecacht. Bei Job-/Grade-Wechsel oder
Override-/Sperr-Änderung wird der Cache automatisch invalidiert
(`MT.Perms.invalidate(identifier)`).
