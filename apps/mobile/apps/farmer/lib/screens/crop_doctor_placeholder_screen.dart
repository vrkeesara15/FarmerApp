import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';

import '../widgets/kisan_widgets.dart';

/// F20 entry of the crop doctor (FM-004 .. FM-006, a later task): the
/// "Check my crop" button and the Crop doctor tab land here until the
/// camera, photo check and result screens (F20–F28) are built.
class CropDoctorPlaceholderScreen extends StatelessWidget {
  /// Creates the screen.
  const CropDoctorPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return KisanTabScaffold(
      tab: KisanTab.cropDoctor,
      title: l10n.kisanNavCropDoctor,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              EmptyState(
                key: const Key('crop-doctor-placeholder'),
                icon: Icons.camera_alt_outlined,
                title: l10n.kisanCropDoctorSoonTitle,
                help: l10n.kisanCropDoctorSoonHelp,
              ),
              AudioButton(
                promptId: 'f20_soon',
                text:
                    '${l10n.kisanCropDoctorSoonTitle}. '
                    '${l10n.kisanCropDoctorSoonHelp}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
