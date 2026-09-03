# T17.18 Dashboard / Performance Scan

Baseline PR #28 is Draft at HEAD `525f2f8b1e084c03aa655d17c83e65428a59503d`,
tree `af95472247ae1d007429ada4411db29ed02fdfc4`.

## Dashboard footprint before removal

| Surface | Baseline cost/exposure |
|---|---:|
| Dashboard-only inputs | 11 |
| Optimizer parameters | 154 |
| Panel implementation | 244 lines / 12,189 bytes |
| Static dashboard controls/labels | 15 chart objects |
| Basket level line/text pairs | up to 16 chart objects |
| Dashboard calls per 500 ms timer | 3 unconditional + 1 on Mobile transition |
| Strategy chart-request reads | 4 per tick |
| Chart event handler | 1 |
| Explicit ChartRedraw | 1 per accepted chart control event |
| WMF arrows | up to 200; owner requires retention |

Static dashboard objects comprise one background, one title, three P/L labels,
nine buttons and one edit field. Dynamic levels comprise eight lines and eight
texts. The 500 ms timer also performs safety/liveness work, so deleting the
timer would be incorrect; only its renderer calls are removable.

## Coupling found

- `CPanel` owned both rendering and manual order/close requests; Strategy paid
  the request/priority branches on every tick even when drawing was disabled.
- `ShowWmfSignals` was coupled to `CPanel::MarkWmfSignal`; owner clarified this
  signal visualization must remain.
- `Cfg.EditLot`, chart-mutated trade toggles and their persisted values became
  dead once buttons were removed. The old persistence offsets must remain
  reserved so RemoteStop/HaltUntil do not shift.
- Non-visual `OnTimer` duties are News refresh, execution watchdog, Recovery
  persistence/exit coordination, Mobile Control, day rollover and halt save.

## Selected architecture

Delete `Panel.mqh`, remove chart-command branches from Strategy and isolate
WMF arrow rendering in `WmfSignalOverlay.mqh`. No dashboard, buttons, level
lines, chart-event handler or redraw remains. `ShowWmfSignals` remains unchanged.

