import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../theme/p4_theme.dart';

/// Full-screen modal PIN lock overlay (`#login`, lines 68-80).
///
/// Uses `SafeArea` and `SingleChildScrollView` with `viewInsets` so the PIN
/// input and buttons are never hidden by the iOS keyboard (§4).
class PinOverlay extends StatefulWidget {
  const PinOverlay({super.key});

  @override
  State<PinOverlay> createState() => _PinOverlayState();
}

class _PinOverlayState extends State<PinOverlay> {
  final TextEditingController _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit(ClockController ctrl) async {
    final pin = _pinController.text;
    _pinController.clear();
    await ctrl.login(pin);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    if (!ctrl.showLoginModal) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Material(
        color: P4Colors.bg.withValues(alpha: 0.96),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: P4Card(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '🔒 Enter PIN',
                        style: TextStyle(
                          color: P4Colors.teal,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('pin_modal_input'),
                        controller: _pinController,
                        autofocus: true,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: P4Colors.text,
                          fontSize: 24,
                          letterSpacing: 4,
                        ),
                        decoration: const InputDecoration(counterText: ''),
                        onSubmitted: (_) => _submit(ctrl),
                      ),
                      if (ctrl.loginMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            ctrl.loginMessage,
                            key: const Key('pin_modal_message'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: P4Colors.dim,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          P4Button(
                            key: const Key('pin_unlock_btn'),
                            label: 'Unlock',
                            onPressed: () => _submit(ctrl),
                          ),
                          const SizedBox(width: 8),
                          P4Button(
                            key: const Key('pin_cancel_btn'),
                            label: 'Cancel',
                            color: P4Colors.slate,
                            onPressed: ctrl.cancelLoginModal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

