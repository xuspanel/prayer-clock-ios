import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../../transport/p4_transport.dart';
import '../theme/p4_theme.dart';

/// Tab 1: Remote (`#t-remote`, lines 131-157).
///
/// Includes playback title (`Stopped`, `♫ <title>`, `🔔 Test: <title>`),
/// elapsed/duration (`f(pos) / f(dur)`), progress bar, transport controls
/// (`prev`, `toggle`, `stop`, `next`), volume slider (`0..21`), and
/// `/music` playlist card with `📁 Folders` and `↻` refresh buttons.
class RemoteTab extends StatelessWidget {
  const RemoteTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    final st = ctrl.lastSt;

    final src = st?['src']?.toString() ?? 'none';
    final isOn = st != null && src != 'none';
    final isTest = st?['test'] == true || st?['test'] == 1;
    final rawTitle = st?['title']?.toString() ?? '';
    final String displayTitle = isOn
        ? '${src == 'music' ? '♫ ' : (isTest ? '🔔 Test: ' : '')}$rawTitle'
        : 'Stopped';

    final num pos = (st?['pos'] is num) ? (st!['pos'] as num) : 0;
    final num dur = (st?['dur'] is num) ? (st!['dur'] as num) : 0;
    final String timeStr =
        '${formatDuration(pos)} / ${dur > 0 ? formatDuration(dur) : '--:--'}';
    final double progressFraction =
        dur > 0 ? (pos.toDouble() / dur.toDouble()).clamp(0.0, 1.0) : 0.0;

    final bool playing = st?['playing'] == true || st?['playing'] == 1;
    final int? rawVol = (st?['vol'] is num) ? (st!['vol'] as num).toInt() : null;
    final int sliderVol = (rawVol ?? 10).clamp(0, 21);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayTitle,
                key: const Key('remote_title'),
                style: const TextStyle(
                  color: P4Colors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                key: const Key('remote_time'),
                style: const TextStyle(color: P4Colors.dim, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  key: const Key('remote_progress'),
                  value: progressFraction,
                  minHeight: 8,
                  backgroundColor: P4Colors.slate,
                  valueColor: const AlwaysStoppedAnimation<Color>(P4Colors.amber),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  P4Button(
                    key: const Key('btn_prev'),
                    label: '⏮',
                    big: true,
                    onPressed: () => ctrl.sendCmd('prev'),
                  ),
                  P4Button(
                    key: const Key('btn_toggle'),
                    label: playing ? '⏸' : '▶',
                    big: true,
                    onPressed: () => ctrl.sendCmd('toggle'),
                  ),
                  P4Button(
                    key: const Key('btn_stop'),
                    label: '■',
                    big: true,
                    color: P4Colors.slate,
                    onPressed: () => ctrl.sendCmd('stop'),
                  ),
                  P4Button(
                    key: const Key('btn_next'),
                    label: '⏭',
                    big: true,
                    onPressed: () => ctrl.sendCmd('next'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('🔉', style: TextStyle(fontSize: 18)),
                  Expanded(
                    child: Slider(
                      key: const Key('slider_volume'),
                      min: 0,
                      max: 21,
                      divisions: 21,
                      value: sliderVol.toDouble(),
                      onChanged: (v) => ctrl.setVolumeDebounced(v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      rawVol != null ? rawVol.toString() : '-',
                      key: const Key('text_volume_val'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: P4Colors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '♫ Playlist (/music)',
                    style: TextStyle(
                      color: P4Colors.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      P4Button(
                        key: const Key('btn_playlist_folders'),
                        label: '📁 Folders',
                        color: P4Colors.slate,
                        small: true,
                        onPressed: () => ctrl.openFilesTab('/music'),
                      ),
                      P4Button(
                        key: const Key('btn_playlist_refresh'),
                        label: '↻',
                        color: P4Colors.slate,
                        small: true,
                        onPressed: ctrl.loadPlaylist,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (ctrl.playlist.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No audio files in /music',
                    key: Key('playlist_empty_text'),
                    style: TextStyle(color: P4Colors.dim, fontSize: 14),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ctrl.playlist.length,
                    itemBuilder: (ctx, i) {
                      final trackName = ctrl.playlist[i];
                      final isCurrent = i == ctrl.currentTrackIndex;
                      return InkWell(
                        key: Key('playlist_item_$i'),
                        onTap: () => ctrl.sendCmd('track', i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: P4Colors.slate),
                            ),
                          ),
                          child: Text(
                            '${i + 1}.  $trackName',
                            style: TextStyle(
                              color: isCurrent ? P4Colors.amber : P4Colors.text,
                              fontWeight:
                                  isCurrent ? FontWeight.bold : FontWeight.normal,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

