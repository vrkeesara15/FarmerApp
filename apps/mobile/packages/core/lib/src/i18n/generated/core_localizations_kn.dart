// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class CoreLocalizationsKn extends CoreLocalizations {
  CoreLocalizationsKn([String locale = 'kn']) : super(locale);

  @override
  String get appNameAgent => 'ಮಿತ್ರ';

  @override
  String get appNameFarmer => 'ಕಿಸಾನ್';

  @override
  String get splashTagline => 'ನಿಮ್ಮ ಹೊಲಕ್ಕೆ ನಂಬಿಕೆಯ ಸಲಹೆ';

  @override
  String get actionContinue => 'ಮುಂದುವರಿಸಿ';

  @override
  String get actionBack => 'ಹಿಂದೆ';

  @override
  String get actionNext => 'ಮುಂದೆ';

  @override
  String get actionRetry => 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ';

  @override
  String get actionCancel => 'ರದ್ದು';

  @override
  String get actionDone => 'ಆಯಿತು';

  @override
  String get actionSkip => 'ಬಿಟ್ಟುಬಿಡಿ';

  @override
  String get actionClose => 'ಮುಚ್ಚಿ';

  @override
  String get loading => 'ಲೋಡ್ ಆಗುತ್ತಿದೆ';

  @override
  String get languagePickerTitle => 'ನಿಮ್ಮ ಭಾಷೆ ಆಯ್ಕೆ ಮಾಡಿ';

  @override
  String get languagePickerSubtitle => 'ಕೇಳಲು ಸ್ಪೀಕರ್ ಒತ್ತಿ';

  @override
  String get languagePlayAudio => 'ಕೇಳಿ';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTelugu => 'తెలుగు';

  @override
  String get languageKannada => 'ಕನ್ನಡ';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageMarathi => 'मराठी';

  @override
  String get languageEnglishName => 'ಇಂಗ್ಲಿಷ್';

  @override
  String get languageTeluguName => 'ತೆಲುಗು';

  @override
  String get languageKannadaName => 'ಕನ್ನಡ';

  @override
  String get languageHindiName => 'ಹಿಂದಿ';

  @override
  String get languageMarathiName => 'ಮರಾಠಿ';

  @override
  String get phoneLoginTitle => 'ನಿಮ್ಮ ಮೊಬೈಲ್ ನಂಬರ್ ನಮೂದಿಸಿ';

  @override
  String get phoneLabel => 'ಮೊಬೈಲ್ ನಂಬರ್';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'ನಾವು SMS ಮೂಲಕ 6 ಅಂಕಿಯ OTP ಕಳುಹಿಸುತ್ತೇವೆ';

  @override
  String get phoneInvalid => 'ಸರಿಯಾದ 10 ಅಂಕಿಯ ಮೊಬೈಲ್ ನಂಬರ್ ನಮೂದಿಸಿ';

  @override
  String get phoneSendOtp => 'OTP ಕಳುಹಿಸಿ';

  @override
  String get otpTitle => 'OTP ನಮೂದಿಸಿ';

  @override
  String otpSubtitle(String phone) {
    return '+91 $phone ಗೆ ಕಳುಹಿಸಲಾಗಿದೆ';
  }

  @override
  String get otpLabel => '6 ಅಂಕಿಯ OTP';

  @override
  String get otpResend => 'OTP ಮತ್ತೆ ಕಳುಹಿಸಿ';

  @override
  String otpResendIn(int seconds) {
    return '$seconds ಸೆಕೆಂಡಿನಲ್ಲಿ ಮತ್ತೆ ಕಳುಹಿಸಿ';
  }

  @override
  String get otpInvalid => 'OTP ತಪ್ಪಾಗಿದೆ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get otpVerify => 'ಪರಿಶೀಲಿಸಿ';

  @override
  String otpDigitLabel(int index) {
    return '6 ರಲ್ಲಿ $indexನೇ ಅಂಕಿ';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count ಪ್ರಯತ್ನಗಳು ಬಾಕಿ';
  }

  @override
  String otpLocked(int minutes) {
    return 'ತುಂಬಾ ತಪ್ಪು ಪ್ರಯತ್ನಗಳು. $minutes ನಿಮಿಷದ ನಂತರ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'ತುಂಬಾ ಬಾರಿ OTP ಕೇಳಿದ್ದೀರಿ. $minutes ನಿಮಿಷದ ನಂತರ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';
  }

  @override
  String get otpExpired => 'ಈ OTP ಅವಧಿ ಮುಗಿದಿದೆ. ಹೊಸದನ್ನು ಕೇಳಿ.';

  @override
  String get phoneNotFound =>
      'ಈ ನಂಬರ್ ನೋಂದಣಿ ಆಗಿಲ್ಲ. ನಿಮ್ಮನ್ನು ಸೇರಿಸಲು ಮ್ಯಾನೇಜರ್‌ಗೆ ಕೇಳಿ.';

  @override
  String get networkError =>
      'ಸಂಪರ್ಕ ಇಲ್ಲ. ನಿಮ್ಮ ನೆಟ್‌ವರ್ಕ್ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get consentTitle => 'ನಿಮ್ಮ ಸ್ಥಳ ಮತ್ತು ಡೇಟಾ';

  @override
  String get consentPoint1 =>
      'ನಾವು ನಿಮ್ಮ ಸ್ಥಳ ಮತ್ತು ಭೇಟಿಯ ಫೋಟೋಗಳನ್ನು ಸಂಗ್ರಹಿಸುತ್ತೇವೆ.';

  @override
  String get consentPoint2 =>
      'ನೀವು ಡ್ಯೂಟಿಯಲ್ಲಿರುವಾಗ ಮಾತ್ರ ಸ್ಥಳ ಸಂಗ್ರಹಿಸುತ್ತೇವೆ.';

  @override
  String get consentPoint3 =>
      'ಇದನ್ನು ಪ್ರಯಾಣ ಭತ್ಯೆ ಮತ್ತು ಭೇಟಿ ಕ್ರೆಡಿಟ್‌ಗಾಗಿ ಬಳಸುತ್ತೇವೆ.';

  @override
  String get consentPoint4 =>
      'ನಿಮ್ಮ ಮ್ಯಾನೇಜರ್ ಮತ್ತು ಮಾಲೀಕರು ನೋಡಬಹುದು. ರೈತರು ನೋಡಲಾರರು.';

  @override
  String get consentAgree => 'ನಾನು ಒಪ್ಪುತ್ತೇನೆ';

  @override
  String get consentPolicyLink => 'ಪೂರ್ಣ ನೀತಿ ಓದಿ';

  @override
  String get consentDataCardTitle => 'ಬೆಳೆ ಸಲಹೆ ನೀಡಲು ನನ್ನ ಡೇಟಾ ಬಳಸಿ';

  @override
  String get consentDataCardBody =>
      'ನಿಮಗೆ ಸಹಾಯ ಮಾಡಲು ನಿಮ್ಮ ಬೆಳೆ ಫೋಟೋ ಮತ್ತು ಹೊಲದ ವಿವರ ನೋಡುತ್ತೇವೆ.';

  @override
  String get consentRequired => 'ಕಡ್ಡಾಯ';

  @override
  String get consentOffersCardTitle => 'ನನಗೆ ಆಫರ್ ಮತ್ತು ಸಲಹೆ ಕಳುಹಿಸಿ';

  @override
  String get consentOffersCardBody =>
      'ಉತ್ಪನ್ನಗಳು ಮತ್ತು ಕೃಷಿ ಸಲಹೆಗಳ ಬಗ್ಗೆ ಸಂದೇಶಗಳು.';

  @override
  String get consentOptional => 'ಐಚ್ಛಿಕ';

  @override
  String get consentReadAloud => 'ಓದಿ ಕೇಳಿಸಿ';

  @override
  String get dutyOn => 'ಡ್ಯೂಟಿಯಲ್ಲಿ';

  @override
  String get dutyOff => 'ಡ್ಯೂಟಿಯಲ್ಲಿ ಇಲ್ಲ';

  @override
  String get dutyGoOn => 'ಡ್ಯೂಟಿ ಶುರು ಮಾಡಿ';

  @override
  String get dutyGoOff => 'ಡ್ಯೂಟಿ ಮುಗಿಸಿ';

  @override
  String dutyElapsed(String duration) {
    return '$duration ಇಂದ ಡ್ಯೂಟಿಯಲ್ಲಿ';
  }

  @override
  String get dutyLocationNote =>
      'ನೀವು ಡ್ಯೂಟಿಯಲ್ಲಿರುವಾಗ ಮಾತ್ರ ಸ್ಥಳ ಆನ್ ಇರುತ್ತದೆ';

  @override
  String get syncSynced => 'ಸಿಂಕ್ ಆಗಿದೆ';

  @override
  String syncPending(int count) {
    return '$count ಬಾಕಿ';
  }

  @override
  String get syncFailed => 'ಸಿಂಕ್ ವಿಫಲವಾಗಿದೆ';

  @override
  String get offlineBanner =>
      'ನೀವು ಆಫ್‌ಲೈನ್ ಇದ್ದೀರಿ. ನಿಮ್ಮ ಕೆಲಸ ಉಳಿಸಲಾಗಿದೆ, ನಂತರ ಸಿಂಕ್ ಆಗುತ್ತದೆ.';

  @override
  String get syncSyncing => 'ಸಿಂಕ್ ಆಗುತ್ತಿದೆ…';

  @override
  String get syncDetailsTitle => 'ಸಿಂಕ್ ವಿವರಗಳು';

  @override
  String get syncNow => 'ಈಗಲೇ ಸಿಂಕ್ ಮಾಡಿ';

  @override
  String syncLastSync(String time) {
    return 'ಕೊನೆಯ ಸಿಂಕ್ $time';
  }

  @override
  String get syncNeverSynced => 'ಇನ್ನೂ ಸಿಂಕ್ ಆಗಿಲ್ಲ';

  @override
  String get syncAllDone => 'ಎಲ್ಲವೂ ಸಿಂಕ್ ಆಗಿದೆ';

  @override
  String get syncAllDoneHelp =>
      'ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿ ಉಳಿಸಿದ ಹೊಸ ರೈತರು, ಹೊಲಗಳು ಮತ್ತು ಫೋಟೋಗಳು ಸರ್ವರ್ ತಲುಪುವವರೆಗೆ ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.';

  @override
  String syncPendingSection(int count) {
    return 'ಸಿಂಕ್‌ಗೆ ಕಾಯುತ್ತಿರುವವು ($count)';
  }

  @override
  String syncFailedSection(int count) {
    return 'ಗಮನ ಬೇಕು ($count)';
  }

  @override
  String get syncWaitingForPhoto => 'ಫೋಟೋ ಅಪ್‌ಲೋಡ್‌ಗೆ ಕಾಯುತ್ತಿದೆ';

  @override
  String syncPhotoUploads(int count) {
    return 'ಅಪ್‌ಲೋಡ್ ಆಗುತ್ತಿರುವ ಫೋಟೋಗಳು: $count';
  }

  @override
  String get syncTransportError =>
      'ಸರ್ವರ್ ತಲುಪಲು ಆಗಲಿಲ್ಲ. ಅದು ತಾನಾಗಿಯೇ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸುತ್ತದೆ.';

  @override
  String syncNextAttempt(String time) {
    return 'ಮುಂದಿನ ಪ್ರಯತ್ನ $time';
  }

  @override
  String syncItemTitle(String action, String entity) {
    return '$action $entity';
  }

  @override
  String get syncActionCreate => 'ಹೊಸ';

  @override
  String get syncActionUpdate => 'ತಿದ್ದಿದ';

  @override
  String get syncActionDelete => 'ಅಳಿಸಿದ';

  @override
  String get syncEntityFarmer => 'ರೈತ';

  @override
  String get syncEntityFarm => 'ಹೊಲ';

  @override
  String get syncEntityCropPlot => 'ಬೆಳೆ ಪ್ಲಾಟ್';

  @override
  String get syncEntityConsent => 'ಒಪ್ಪಿಗೆ';

  @override
  String get syncEntityOther => 'ಐಟಂ';

  @override
  String syncSavedAt(String time) {
    return 'ಉಳಿಸಿದ್ದು $time';
  }

  @override
  String get syncRejectedDefault =>
      'ಸರ್ವರ್ ಈ ಐಟಂ ಅನ್ನು ಸ್ವೀಕರಿಸಲಿಲ್ಲ. ತಿದ್ದಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get syncRetryAll => 'ಎಲ್ಲವನ್ನೂ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ';

  @override
  String get syncDiscard => 'ಬಿಟ್ಟುಬಿಡಿ';

  @override
  String get visitVerified => 'ಪರಿಶೀಲಿತ';

  @override
  String get visitPartial => 'ಭಾಗಶಃ';

  @override
  String get visitUnverified => 'ಪರಿಶೀಲಿಸಿಲ್ಲ';

  @override
  String visitScore(int score) {
    return '100 ರಲ್ಲಿ $score ಅಂಕ';
  }

  @override
  String visitDurationMinutes(int minutes) {
    return '$minutes ನಿಮಿ';
  }

  @override
  String get visitPurposeAdvisory => 'ಸಲಹೆ';

  @override
  String get visitPurposeScouting => 'ಹೊಲ ಪರಿಶೀಲನೆ';

  @override
  String get visitPurposeDemo => 'ಡೆಮೊ';

  @override
  String get visitPurposeCollection => 'ವಸೂಲಿ';

  @override
  String get visitPurposeSale => 'ಮಾರಾಟ';

  @override
  String get visitPurposeMeeting => 'ಸಭೆ';

  @override
  String get proofGeofence => 'ಹೊಲದ ಗಡಿಯ ಒಳಗೆ';

  @override
  String get proofGeofenceMissing => 'ನೀವು ಹೊಲದ ಗಡಿಯ ಹೊರಗಿದ್ದಿರಿ';

  @override
  String get proofPhoto => 'ಫೋಟೋ ತೆಗೆದಿದೆ';

  @override
  String get proofPhotoMissing => 'ಭೇಟಿಯಲ್ಲಿ ಫೋಟೋ ತೆಗೆದಿಲ್ಲ';

  @override
  String get proofFarmerConfirmed => 'ರೈತರು ದೃಢಪಡಿಸಿದ್ದಾರೆ';

  @override
  String get proofFarmerConfirmedMissing => 'ರೈತರು ಭೇಟಿಯನ್ನು ದೃಢಪಡಿಸಿಲ್ಲ';

  @override
  String get proofDuration => 'ಹೊಲದಲ್ಲಿ ಕನಿಷ್ಠ ಸಮಯ ಪೂರ್ಣ';

  @override
  String get proofDurationMissing => 'ಭೇಟಿ 10 ನಿಮಿಷಕ್ಕಿಂತ ಕಡಿಮೆ';

  @override
  String get proofDone => 'ಆಗಿದೆ';

  @override
  String get proofMissing => 'ಇಲ್ಲ';

  @override
  String get cameraHoldSteady => 'ಅಲುಗಾಡಿಸದೆ ಹಿಡಿಯಿರಿ';

  @override
  String get cameraGoodLight => 'ಒಳ್ಳೆಯ ಬೆಳಕು';

  @override
  String get cameraFillFrame => 'ಫ್ರೇಮ್ ತುಂಬಿಸಿ';

  @override
  String get cameraLeafFrame => 'ಎಲೆಯನ್ನು ಫ್ರೇಮ್ ಒಳಗೆ ಇಡಿ';

  @override
  String get photoReviewHeading => 'ನಿಮ್ಮ ಫೋಟೋ ಪರಿಶೀಲಿಸಿ';

  @override
  String photoReviewTitle(int index, int total) {
    return 'ಫೋಟೋ $index / $total';
  }

  @override
  String get photoQualityOk => 'ಒಳ್ಳೆಯ ಫೋಟೋ';

  @override
  String get photoQualityBlurry => 'ಮಸುಕಾಗಿದೆ';

  @override
  String get photoQualityDark => 'ತುಂಬಾ ಕತ್ತಲಾಗಿದೆ';

  @override
  String get photoQualityChecking => 'ಫೋಟೋ ಪರಿಶೀಲಿಸುತ್ತಿದ್ದೇವೆ';

  @override
  String get photoTipBlurry =>
      'ಫೋನ್ ಅನ್ನು ಸ್ಥಿರವಾಗಿ ಹಿಡಿದು, ಎಲೆಯ ಮೇಲೆ ಒತ್ತಿ ಫೋಕಸ್ ಮಾಡಿ ಮತ್ತೆ ತೆಗೆಯಿರಿ';

  @override
  String get photoTipDark =>
      'ಹೆಚ್ಚು ಬೆಳಕಿರುವ ಕಡೆ ಹೋಗಿ, ನೆರಳಿನಿಂದ ಹೊರಬಂದು ಮತ್ತೆ ತೆಗೆಯಿರಿ';

  @override
  String get photoTipOk => 'ಫೋಟೋ ಚೆನ್ನಾಗಿದೆ';

  @override
  String get photoRetake => 'ಮತ್ತೆ ತೆಗೆಯಿರಿ';

  @override
  String get photoUse => 'ಈ ಫೋಟೋ ಬಳಸಿ';

  @override
  String photoSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String photoDimensions(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get confidenceHigh => 'ಹೆಚ್ಚು ವಿಶ್ವಾಸ';

  @override
  String get confidenceMedium => 'ಮಧ್ಯಮ ವಿಶ್ವಾಸ';

  @override
  String get confidenceLow => 'ತಾತ್ಕಾಲಿಕ';

  @override
  String get diagnosisSymptomsTitle => 'ಈ ಲಕ್ಷಣಗಳನ್ನು ನೋಡಿ';

  @override
  String get diagnosisProvisionalNote =>
      'ನಮ್ಮ ತಜ್ಞರು 24 ಗಂಟೆಯೊಳಗೆ ದೃಢಪಡಿಸುತ್ತಾರೆ';

  @override
  String get diagnosisProblem => 'ಸಮಸ್ಯೆ';

  @override
  String get treatmentOrganic => 'ಸಾವಯವ';

  @override
  String get treatmentChemical => 'ರಾಸಾಯನಿಕ';

  @override
  String get treatmentActiveIngredient => 'ಕ್ರಿಯಾಶೀಲ ಅಂಶ';

  @override
  String get treatmentDosePerAcre => 'ಎಕರೆಗೆ';

  @override
  String get treatmentDosePerTank => '15 ಲೀ ಟ್ಯಾಂಕ್‌ಗೆ';

  @override
  String treatmentSafetyInterval(int days) {
    return 'ಕೊಯ್ಲಿಗೆ ಮೊದಲು $days ದಿನ ಕಾಯಿರಿ';
  }

  @override
  String get treatmentPpeGloves => 'ಕೈಗವಸು';

  @override
  String get treatmentPpeMask => 'ಮಾಸ್ಕ್';

  @override
  String get treatmentPpeGoggles => 'ಕನ್ನಡಕ';

  @override
  String get treatmentPpeTitle => 'ಧರಿಸಿ';

  @override
  String get ownBrand => 'ಸ್ವಂತ ಬ್ರಾಂಡ್';

  @override
  String get productAdd => 'ಸೇರಿಸಿ';

  @override
  String get productAdded => 'ಸೇರಿಸಿದೆ';

  @override
  String productStockAtStore(int count, String store) {
    return '$store ನಲ್ಲಿ $count ಸ್ಟಾಕ್ ಇದೆ';
  }

  @override
  String get productOutOfStock => 'ಸ್ಟಾಕ್ ಇಲ್ಲ';

  @override
  String get productPack => 'ಪ್ಯಾಕ್';

  @override
  String cartItems(int count) {
    return '$count ವಸ್ತುಗಳು';
  }

  @override
  String get cartTotal => 'ಒಟ್ಟು';

  @override
  String get cartCheckout => 'ಪಾವತಿಸಿ';

  @override
  String get paymentMethodTitle => 'ಹೇಗೆ ಪಾವತಿಸುತ್ತೀರಿ?';

  @override
  String get paymentUpiQr => 'UPI QR';

  @override
  String get paymentUpiQrHint => 'ಸ್ಕ್ಯಾನ್ ಮಾಡಿ ಈಗಲೇ ಪಾವತಿಸಿ';

  @override
  String get paymentLink => 'ಪಾವತಿ ಲಿಂಕ್';

  @override
  String get paymentLinkHint => 'SMS ಅಥವಾ WhatsApp ಮೂಲಕ ಕಳುಹಿಸಿ';

  @override
  String get paymentCash => 'ನಗದು';

  @override
  String get paymentCashHint => 'ನಗದು ಪಡೆದು ರಸೀದಿ ಕೊಡಿ';

  @override
  String get paymentCredit => 'ಸಾಲ';

  @override
  String get paymentCreditHint => 'ರೈತರ ಖಾತೆಗೆ ಸೇರಿಸಿ';

  @override
  String get upiWaiting => 'ಪಾವತಿಗಾಗಿ ಕಾಯುತ್ತಿದ್ದೇವೆ';

  @override
  String get upiPaid => 'ಪಾವತಿ ಬಂದಿದೆ';

  @override
  String get upiFailed => 'ಪಾವತಿ ವಿಫಲವಾಗಿದೆ';

  @override
  String upiExpiresIn(String time) {
    return '$time ನಲ್ಲಿ ಅವಧಿ ಮುಗಿಯುತ್ತದೆ';
  }

  @override
  String get upiAmount => 'ಮೊತ್ತ';

  @override
  String get upiScanHint => 'ಯಾವುದೇ UPI ಆ್ಯಪ್‌ನಿಂದ ಸ್ಕ್ಯಾನ್ ಮಾಡಲು ರೈತರಿಗೆ ಹೇಳಿ';

  @override
  String get upiRetry => 'ಹೊಸ QR ತೋರಿಸಿ';

  @override
  String get khataBalance => 'ಬಾಕಿ ಮೊತ್ತ';

  @override
  String khataDueDate(String date) {
    return '$date ಒಳಗೆ ಪಾವತಿಸಬೇಕು';
  }

  @override
  String get khataDebit => 'ಕೊಟ್ಟದ್ದು';

  @override
  String get khataCredit => 'ಬಂದದ್ದು';

  @override
  String get khataNoEntries => 'ಇನ್ನೂ ನಮೂದುಗಳಿಲ್ಲ';

  @override
  String get khataPayNow => 'ಈಗಲೇ ಪಾವತಿಸಿ';

  @override
  String get khataCollect => 'ವಸೂಲಿ ಮಾಡಿ';

  @override
  String get emptyDefaultTitle => 'ಇನ್ನೂ ಏನೂ ಇಲ್ಲ';

  @override
  String get emptyDefaultHelp => 'ನೀವು ಸೇರಿಸಿದ ಮೇಲೆ ಇಲ್ಲಿ ಕಾಣುತ್ತವೆ.';

  @override
  String get errorTitle => 'ಏನೋ ತಪ್ಪಾಗಿದೆ';

  @override
  String get errorHelp => 'ನಿಮ್ಮ ಸಂಪರ್ಕ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get ratingTitle => 'ನಿಮ್ಮ ಭೇಟಿಗೆ ರೇಟಿಂಗ್ ಕೊಡಿ';

  @override
  String get rating1 => 'ತುಂಬಾ ಕೆಟ್ಟದು';

  @override
  String get rating2 => 'ಕೆಟ್ಟದು';

  @override
  String get rating3 => 'ಪರವಾಗಿಲ್ಲ';

  @override
  String get rating4 => 'ಒಳ್ಳೆಯದು';

  @override
  String get rating5 => 'ತುಂಬಾ ಒಳ್ಳೆಯದು';

  @override
  String stepperStepOf(int current, int total) {
    return '$total ರಲ್ಲಿ $currentನೇ ಹಂತ';
  }

  @override
  String farmerLastVisit(String date) {
    return 'ಕೊನೆಯ ಭೇಟಿ $date';
  }

  @override
  String get farmerNoVisit => 'ಇನ್ನೂ ಭೇಟಿ ಇಲ್ಲ';

  @override
  String farmerBalanceDue(String amount) {
    return 'ಬಾಕಿ $amount';
  }

  @override
  String get farmerVillage => 'ಹಳ್ಳಿ';

  @override
  String get statTrendUp => 'ಹೆಚ್ಚಳ';

  @override
  String get statTrendDown => 'ಇಳಿಕೆ';

  @override
  String get statTrendFlat => 'ಬದಲಾವಣೆ ಇಲ್ಲ';

  @override
  String get stageSowing => 'ಬಿತ್ತನೆ';

  @override
  String get stageVegetative => 'ಬೆಳವಣಿಗೆ';

  @override
  String get stageFlowering => 'ಹೂವು';

  @override
  String get stageFruiting => 'ಕಾಯಿ';

  @override
  String get stageHarvest => 'ಕೊಯ್ಲು';

  @override
  String get settingsTheme => 'ಥೀಮ್';

  @override
  String get themeLight => 'ಲೈಟ್';

  @override
  String get themeSunlight => 'ಬಿಸಿಲು';

  @override
  String get settingsTitle => 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get settingsLanguage => 'ಭಾಷೆ';

  @override
  String get skeletonLoading => 'ವಿಷಯ ಲೋಡ್ ಆಗುತ್ತಿದೆ';

  @override
  String get farmersTitle => 'ರೈತರು';

  @override
  String get farmersSearchHint => 'ಹೆಸರು, ಫೋನ್ ಅಥವಾ ಹಳ್ಳಿ ಹುಡುಕಿ';

  @override
  String get farmersAddFarmer => 'ರೈತರನ್ನು ಸೇರಿಸಿ';

  @override
  String get farmersEmptyTitle => 'ಇನ್ನೂ ರೈತರಿಲ್ಲ';

  @override
  String get farmersEmptyHelp =>
      'ಭೇಟಿಗಳು ಮತ್ತು ಆರ್ಡರ್‌ಗಳನ್ನು ಆರಂಭಿಸಲು ಮೊದಲ ರೈತರನ್ನು ಸೇರಿಸಿ.';

  @override
  String get farmersNoResults => 'ನಿಮ್ಮ ಹುಡುಕಾಟಕ್ಕೆ ಹೊಂದುವ ರೈತರಿಲ್ಲ';

  @override
  String get farmersFilterVillage => 'ಹಳ್ಳಿ';

  @override
  String get farmersFilterCrop => 'ಬೆಳೆ';

  @override
  String get farmersFilterAll => 'ಎಲ್ಲಾ';

  @override
  String farmersCount(int count) {
    return '$count ರೈತರು';
  }

  @override
  String get farmerPendingSync => 'ಆನ್‌ಲೈನ್ ಆದಾಗ ಸಿಂಕ್ ಆಗುತ್ತದೆ';

  @override
  String get farmerPhoneUnverified => 'ಫೋನ್ ಪರಿಶೀಲಿಸಿಲ್ಲ';

  @override
  String get farmerRejected => 'ಗಮನ ಅಗತ್ಯ';

  @override
  String get regTitle => 'ರೈತರನ್ನು ಸೇರಿಸಿ';

  @override
  String get regStepBasics => 'ರೈತರ ವಿವರಗಳು';

  @override
  String get regStepBoundary => 'ಹೊಲದ ಗಡಿ';

  @override
  String get regStepCrops => 'ಬೆಳೆಗಳು';

  @override
  String get regStepConsent => 'ಒಪ್ಪಿಗೆ';

  @override
  String get regStepReview => 'ಪರಿಶೀಲಿಸಿ ಉಳಿಸಿ';

  @override
  String get regResumeDraft => 'ನೀವು ನಿಲ್ಲಿಸಿದ ಕಡೆಯಿಂದ ಮುಂದುವರಿಯುತ್ತಿದೆ';

  @override
  String get regDiscardDraft => 'ಡ್ರಾಫ್ಟ್ ತೆಗೆದುಹಾಕಿ';

  @override
  String get regFixIssues => 'ಮುಂದುವರಿಯಲು ಗುರುತಿಸಿದ ಕ್ಷೇತ್ರಗಳನ್ನು ಸರಿಪಡಿಸಿ';

  @override
  String get regNameLabel => 'ರೈತರ ಹೆಸರು';

  @override
  String get regNameHint => 'ಗುರುತಿನ ಚೀಟಿಯಲ್ಲಿರುವಂತೆ';

  @override
  String get regPhoneLabel => 'ರೈತರ ಮೊಬೈಲ್ ಸಂಖ್ಯೆ';

  @override
  String get regPhoneHelper => 'ರೈತರಿಗೆ OTP ಕಳುಹಿಸಲಾಗುತ್ತದೆ';

  @override
  String get regSendOtpToFarmer => 'ರೈತರಿಗೆ OTP ಕಳುಹಿಸಿ';

  @override
  String get regOtpSent => 'ರೈತರಿಗೆ OTP ಕಳುಹಿಸಲಾಗಿದೆ. ಅವರಿಂದ ಕೋಡ್ ಕೇಳಿ.';

  @override
  String get regPhoneVerified => 'ಫೋನ್ ಪರಿಶೀಲಿಸಲಾಗಿದೆ';

  @override
  String get regVerifyLater => 'ನಂತರ ಪರಿಶೀಲಿಸಿ';

  @override
  String get regVerifyLaterNote =>
      'ಸಿಗ್ನಲ್ ಇಲ್ಲವೇ? ಈಗ ಉಳಿಸಿ, ರೈತರ ಪ್ರೊಫೈಲ್‌ನಿಂದ ಫೋನ್ ಪರಿಶೀಲಿಸಿ.';

  @override
  String get regVerifyLaterChosen => 'ನಂತರ ಪರಿಶೀಲಿಸಲಾಗುತ್ತದೆ';

  @override
  String get regDuplicatePhone => 'ಈ ಸಂಖ್ಯೆಯ ರೈತರು ಈಗಾಗಲೇ ಇದ್ದಾರೆ';

  @override
  String get regDuplicateOpen => 'ಇರುವ ರೈತರನ್ನು ತೆರೆಯಿರಿ';

  @override
  String get regVillageLabel => 'ಹಳ್ಳಿ';

  @override
  String get regVillageHint => 'ಹಳ್ಳಿ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get regVillageTyped => 'ಹಳ್ಳಿಯ ಹೆಸರು';

  @override
  String get regVillageNoneSynced =>
      'ಮೊದಲ ಸಿಂಕ್ ನಂತರ ಹಳ್ಳಿಗಳು ಲೋಡ್ ಆಗುತ್ತವೆ. ಸದ್ಯಕ್ಕೆ ಹಳ್ಳಿಯ ಹೆಸರು ಟೈಪ್ ಮಾಡಿ.';

  @override
  String get regLandmarkLabel => 'ಗುರುತು';

  @override
  String get regLandmarkHint => 'ದೇವಸ್ಥಾನ, ಶಾಲೆಯ ಹತ್ತಿರ…';

  @override
  String get regLanguageLabel => 'ರೈತರ ಭಾಷೆ';

  @override
  String get regOwnershipLabel => 'ಭೂಮಿ';

  @override
  String get regBoundaryWalk => 'ಸುತ್ತಲೂ ನಡೆಯಿರಿ';

  @override
  String get regBoundaryTap => 'ಮೂಲೆಗಳನ್ನು ಒತ್ತಿ';

  @override
  String get regStartWalk => 'ನಡೆಯಲು ಆರಂಭಿಸಿ';

  @override
  String get regStopWalk => 'ವಿರಾಮ';

  @override
  String get regClosePolygon => 'ಗಡಿ ಮುಚ್ಚಿ';

  @override
  String get regUndoPoint => 'ಬಿಂದು ಹಿಂತೆಗೆಯಿರಿ';

  @override
  String get regClearBoundary => 'ಅಳಿಸಿ';

  @override
  String regPointsCount(int count) {
    return '$count ಬಿಂದುಗಳು';
  }

  @override
  String regAccuracy(int metres) {
    return 'GPS ನಿಖರತೆ ±$metres ಮೀ';
  }

  @override
  String get regAccuracyWaiting => 'GPS ಗಾಗಿ ಕಾಯುತ್ತಿದೆ…';

  @override
  String get regLocationOff => 'ಗಡಿ ನಡೆಯಲು ಲೊಕೇಶನ್ ಆನ್ ಮಾಡಿ';

  @override
  String get regLocationDenied => 'ಗಡಿ ನಡೆಯಲು ಲೊಕೇಶನ್ ಅನುಮತಿ ಬೇಕು';

  @override
  String get regTapHint => 'ನಕ್ಷೆಯಲ್ಲಿ ಹೊಲದ ನಾಲ್ಕು ಮೂಲೆಗಳನ್ನು ಒತ್ತಿ';

  @override
  String get regWalkHint =>
      'ಹೊಲದ ಅಂಚಿನುದ್ದಕ್ಕೂ ನಡೆಯಿರಿ. ನೀವು ನಡೆದಂತೆ ಬಿಂದುಗಳು ಸೇರುತ್ತವೆ.';

  @override
  String regComputedArea(String acres) {
    return 'ಅಳೆದ ವಿಸ್ತೀರ್ಣ $acres ಎಕರೆ';
  }

  @override
  String get regAreaLabel => 'ವಿಸ್ತೀರ್ಣ ಎಕರೆಗಳಲ್ಲಿ';

  @override
  String get regAreaHint => 'ರೈತರು ಹೇಳಿದಂತೆ';

  @override
  String get regUseMeasured => 'ಅಳೆದದ್ದನ್ನು ಬಳಸಿ';

  @override
  String get regAreaWarning =>
      'ನಮೂದಿಸಿದ ವಿಸ್ತೀರ್ಣವು ಅಳೆದ ವಿಸ್ತೀರ್ಣಕ್ಕಿಂತ 30% ಕ್ಕೂ ಹೆಚ್ಚು ವ್ಯತ್ಯಾಸವಿದೆ. ಉಳಿಸುವ ಮೊದಲು ಪರಿಶೀಲಿಸಿ.';

  @override
  String get regBoundaryInvalid =>
      'ಗಡಿ ತನ್ನನ್ನೇ ದಾಟುತ್ತಿದೆ. ಕೊನೆಯ ಬಿಂದುಗಳನ್ನು ಹಿಂತೆಗೆದು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get regFarmNameLabel => 'ಹೊಲದ ಹೆಸರು (ಐಚ್ಛಿಕ)';

  @override
  String get regFarmNameHint => 'ಮನೆ ಹೊಲ';

  @override
  String get regSoilLabel => 'ಮಣ್ಣಿನ ಪ್ರಕಾರ';

  @override
  String get regIrrigationLabel => 'ನೀರಾವರಿ';

  @override
  String get regFarmPhoto => 'ಹೊಲದ ಫೋಟೋ (ಐಚ್ಛಿಕ)';

  @override
  String get regTakePhoto => 'ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get regPhotoAdded => 'ಫೋಟೋ ಸೇರಿಸಲಾಗಿದೆ';

  @override
  String get regPhotoRemove => 'ತೆಗೆದುಹಾಕಿ';

  @override
  String regFarmPhotosCount(int count) {
    return '$count ಫೋಟೋಗಳು';
  }

  @override
  String get regCropsHelp =>
      'ಈ ಋತುವಿನಲ್ಲಿ ಈ ಹೊಲದಲ್ಲಿ ಬೆಳೆಯುತ್ತಿರುವ ಪ್ರತಿ ಬೆಳೆಯನ್ನು ಸೇರಿಸಿ.';

  @override
  String get regAddCrop => 'ಬೆಳೆ ಸೇರಿಸಿ';

  @override
  String get regCropLabel => 'ಬೆಳೆ';

  @override
  String get regVarietyLabel => 'ತಳಿ';

  @override
  String get regVarietyHint => 'ಉದಾ. MTU-1010';

  @override
  String get regSowingDateLabel => 'ಬಿತ್ತನೆ ದಿನಾಂಕ';

  @override
  String get regSowingDateHint => 'DD-MM-YYYY';

  @override
  String regSeasonAuto(String season) {
    return 'ಋತು: $season';
  }

  @override
  String get regPlotAreaLabel => 'ವಿಸ್ತೀರ್ಣ (ಎಕರೆ, ಐಚ್ಛಿಕ)';

  @override
  String get regRemoveCrop => 'ಬೆಳೆ ತೆಗೆದುಹಾಕಿ';

  @override
  String regPlotTitle(int index) {
    return 'ಬೆಳೆ $index';
  }

  @override
  String get regAddFarm => 'ಇನ್ನೊಂದು ಹೊಲ ಸೇರಿಸಿ';

  @override
  String regFarmsCount(int count) {
    return '$count ಹೊಲಗಳು';
  }

  @override
  String regFarmIndex(int index) {
    return 'ಹೊಲ $index';
  }

  @override
  String get regConsentIntro => 'ಇದನ್ನು ರೈತರಿಗೆ ಅವರ ಭಾಷೆಯಲ್ಲಿ ಓದಿ ಹೇಳಿ.';

  @override
  String get regConsentNotice =>
      'ಬೆಳೆ ಸಲಹೆ ನೀಡಲು ಮತ್ತು ಭೇಟಿ ದಾಖಲೆಗಳನ್ನು ಇಡಲು ನಿಮ್ಮ ಹೆಸರು, ಫೋನ್, ಹಳ್ಳಿ ಮತ್ತು ಹೊಲದ ವಿವರಗಳನ್ನು ನಾವು ಇಟ್ಟುಕೊಳ್ಳುತ್ತೇವೆ. ಯಾವಾಗ ಬೇಕಾದರೂ ನಿಲ್ಲಿಸಲು ನಮ್ಮನ್ನು ಕೇಳಬಹುದು.';

  @override
  String get regConsentMarketingNotice =>
      'ನಿಮ್ಮ ಅನುಮತಿಯೊಂದಿಗೆ SMS ಅಥವಾ WhatsApp ಮೂಲಕ ಆಫರ್‌ಗಳು ಮತ್ತು ಕೃಷಿ ಸಲಹೆಗಳನ್ನೂ ಕಳುಹಿಸುತ್ತೇವೆ.';

  @override
  String get regConsentGiven => 'ರೈತರು ಒಪ್ಪುತ್ತಾರೆ';

  @override
  String get regReviewFarmer => 'ರೈತರು';

  @override
  String get regReviewFarms => 'ಹೊಲಗಳು ಮತ್ತು ಬೆಳೆಗಳು';

  @override
  String get regReviewConsent => 'ಒಪ್ಪಿಗೆ';

  @override
  String get regReviewSyncNote =>
      'ಈಗ ಈ ಫೋನ್‌ನಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ; ನೆಟ್‌ವರ್ಕ್ ಬಂದಾಗ ಸರ್ವರ್‌ಗೆ ಕಳುಹಿಸಲಾಗುತ್ತದೆ.';

  @override
  String get regSave => 'ರೈತರನ್ನು ಉಳಿಸಿ';

  @override
  String get regSaveFarm => 'ಹೊಲ ಉಳಿಸಿ';

  @override
  String get regEdit => 'ಸಂಪಾದಿಸಿ';

  @override
  String get regSaved => 'ರೈತರನ್ನು ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get regIssueName => 'ರೈತರ ಹೆಸರು ನಮೂದಿಸಿ';

  @override
  String get regIssuePhoneUnverified =>
      'ಫೋನ್ ಪರಿಶೀಲಿಸಿ ಅಥವಾ ನಂತರ ಪರಿಶೀಲಿಸಿ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get regIssueVillage => 'ಹಳ್ಳಿ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get regIssueLanguage => 'ರೈತರ ಭಾಷೆ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get regIssueBoundary => 'ಗಡಿಯ ಕನಿಷ್ಠ 3 ಬಿಂದುಗಳನ್ನು ಗುರುತಿಸಿ';

  @override
  String get regIssueArea => 'ವಿಸ್ತೀರ್ಣವನ್ನು ಎಕರೆಗಳಲ್ಲಿ ನಮೂದಿಸಿ';

  @override
  String get regIssueCrop => 'ಕನಿಷ್ಠ ಒಂದು ಬೆಳೆ ಸೇರಿಸಿ';

  @override
  String get regIssueSowingDate => 'ಪ್ರತಿ ಬೆಳೆಗೆ ಬಿತ್ತನೆ ದಿನಾಂಕ ನಮೂದಿಸಿ';

  @override
  String get regIssueConsent => 'ನೋಂದಣಿಗೆ ಡೇಟಾ ಒಪ್ಪಿಗೆ ಅಗತ್ಯ';

  @override
  String get soilBlack => 'ಕಪ್ಪು ಮಣ್ಣು';

  @override
  String get soilRed => 'ಕೆಂಪು ಮಣ್ಣು';

  @override
  String get soilSandy => 'ಮರಳು ಮಣ್ಣು';

  @override
  String get soilLoamy => 'ಲೋಮ್ ಮಣ್ಣು';

  @override
  String get soilClay => 'ಜೇಡಿ ಮಣ್ಣು';

  @override
  String get soilAlluvial => 'ಮೆಕ್ಕಲು ಮಣ್ಣು';

  @override
  String get soilLaterite => 'ಲ್ಯಾಟರೈಟ್ ಮಣ್ಣು';

  @override
  String get irrigationRainfed => 'ಮಳೆಯಾಶ್ರಿತ';

  @override
  String get irrigationBorewell => 'ಕೊಳವೆಬಾವಿ';

  @override
  String get irrigationCanal => 'ಕಾಲುವೆ';

  @override
  String get irrigationTank => 'ಕೆರೆ';

  @override
  String get irrigationOpenWell => 'ತೆರೆದ ಬಾವಿ';

  @override
  String get irrigationDrip => 'ಹನಿ ನೀರಾವರಿ';

  @override
  String get irrigationSprinkler => 'ತುಂತುರು ನೀರಾವರಿ';

  @override
  String get ownershipOwn => 'ಸ್ವಂತ';

  @override
  String get ownershipLeased => 'ಗುತ್ತಿಗೆ';

  @override
  String get seasonKharif => 'ಖಾರಿಫ್';

  @override
  String get seasonRabi => 'ರಬಿ';

  @override
  String get seasonZaid => 'ಜೈದ್ (ಬೇಸಿಗೆ)';

  @override
  String get profileTabOverview => 'ಅವಲೋಕನ';

  @override
  String get profileTabVisits => 'ಭೇಟಿಗಳು';

  @override
  String get profileTabDiagnoses => 'ರೋಗ ನಿರ್ಣಯಗಳು';

  @override
  String get profileTabOrders => 'ಆರ್ಡರ್‌ಗಳು';

  @override
  String get profileTabKhata => 'ಖಾತೆ';

  @override
  String get profileStartVisit => 'ಭೇಟಿ ಆರಂಭಿಸಿ';

  @override
  String get profileScout => 'ಬೆಳೆ ವೀಕ್ಷಣೆ';

  @override
  String get profileNewOrder => 'ಹೊಸ ಆರ್ಡರ್';

  @override
  String get profileCollect => 'ವಸೂಲಿ';

  @override
  String get profileComingSoon => 'ಮುಂದಿನ ಅಪ್‌ಡೇಟ್‌ನಲ್ಲಿ ಬರುತ್ತದೆ';

  @override
  String get profileVisitsEmpty => 'ಇನ್ನೂ ಭೇಟಿಗಳಿಲ್ಲ';

  @override
  String get profileDiagnosesEmpty => 'ಇನ್ನೂ ರೋಗ ನಿರ್ಣಯಗಳಿಲ್ಲ';

  @override
  String get profileOrdersEmpty => 'ಇನ್ನೂ ಆರ್ಡರ್‌ಗಳಿಲ್ಲ';

  @override
  String get profileKhataEmpty => 'ಇನ್ನೂ ಖಾತೆ ನಮೂದುಗಳಿಲ್ಲ';

  @override
  String get profilePhone => 'ಫೋನ್';

  @override
  String get profileLandmark => 'ಗುರುತು';

  @override
  String get profileLanguage => 'ಭಾಷೆ';

  @override
  String get profileOwnership => 'ಭೂಮಿ';

  @override
  String get profileFarms => 'ಹೊಲಗಳು';

  @override
  String profileAcres(String acres) {
    return '$acres ಎಕರೆ';
  }

  @override
  String get profileAddFarm => 'ಹೊಲ ಸೇರಿಸಿ';

  @override
  String get profileEditFarm => 'ಹೊಲ ಸಂಪಾದಿಸಿ';

  @override
  String profileFarmPlots(int count) {
    return '$count ಬೆಳೆಗಳು';
  }

  @override
  String get profileNoFarms => 'ಇನ್ನೂ ಹೊಲಗಳಿಲ್ಲ';

  @override
  String get profileDuplicateTitle => 'ನಕಲು — ವಿಲೀನಗೊಳಿಸಬೇಕೇ?';

  @override
  String get profileDuplicateBody =>
      'ಈ ಸಂಖ್ಯೆಯ ರೈತರು ಸರ್ವರ್‌ನಲ್ಲಿ ಈಗಾಗಲೇ ಇದ್ದಾರೆ. ಇರುವ ದಾಖಲೆಯನ್ನು ತೆರೆದು ವಿವರಗಳನ್ನು ವಿಲೀನಗೊಳಿಸಿ.';

  @override
  String get profileRejectedTitle => 'ಸಿಂಕ್ ತಿರಸ್ಕರಿಸಲಾಗಿದೆ';

  @override
  String get profileRejectedHelp =>
      'ಸರಿಪಡಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಲು ಸಿಂಕ್ ವಿವರಗಳನ್ನು ತೆರೆಯಿರಿ.';

  @override
  String get profileNotFound => 'ರೈತರು ಸಿಗಲಿಲ್ಲ';

  @override
  String get profileVerifyPhone => 'ಫೋನ್ ಪರಿಶೀಲಿಸಿ';

  @override
  String get consentGiven => 'ನೀಡಲಾಗಿದೆ';

  @override
  String get consentNotGiven => 'ನೀಡಿಲ್ಲ';

  @override
  String get farmEditTitle => 'ಹೊಲ ಸಂಪಾದಿಸಿ';

  @override
  String get farmAddTitle => 'ಹೊಲ ಸೇರಿಸಿ';

  @override
  String get mapNoBoundary => 'ಇನ್ನೂ ಗಡಿ ಇಲ್ಲ';

  @override
  String get mapAttribution => '© OpenStreetMap ಕೊಡುಗೆದಾರರು';

  @override
  String get mapCurrentPosition => 'ನಿಮ್ಮ ಸ್ಥಾನ';

  @override
  String mapCorner(int index) {
    return 'ಮೂಲೆ $index';
  }

  @override
  String get mapFarmBoundary => 'ಹೊಲದ ಗಡಿ';

  @override
  String get dutyNotificationTitle => 'ಕರ್ತವ್ಯದಲ್ಲಿ — ಲೊಕೇಶನ್ ಆನ್';

  @override
  String get dutyChannelName => 'ಕರ್ತವ್ಯ';

  @override
  String get dutyAlertsChannelName => 'ಕರ್ತವ್ಯ ಎಚ್ಚರಿಕೆಗಳು';

  @override
  String get dutyPromptTitle => 'ಇನ್ನೂ ಕರ್ತವ್ಯದಲ್ಲಿದ್ದೀರಾ?';

  @override
  String dutyPromptBody(String time) {
    return '$timeಕ್ಕೆ ಕೊನೆಗೊಳ್ಳುತ್ತದೆ';
  }

  @override
  String get dutyEndedTitle => 'ಕರ್ತವ್ಯ ಮುಗಿಯಿತು';

  @override
  String dutyAutoEndedBody(String time) {
    return 'ನಿಮ್ಮ ದಿನ $timeಕ್ಕೆ ಸ್ವಯಂಚಾಲಿತವಾಗಿ ಮುಗಿಯಿತು.';
  }

  @override
  String get dutyServerEndedBody =>
      'ಸರ್ವರ್ ನಿಮ್ಮ ಕರ್ತವ್ಯವನ್ನು ಕೊನೆಗೊಳಿಸಿತು (ನಿಷ್ಕ್ರಿಯತೆ ಅಥವಾ ದಿನದ ಅಂತ್ಯ).';

  @override
  String dutyAutoEndAt(String time) {
    return '$timeಕ್ಕೆ ಸ್ವಯಂಚಾಲಿತವಾಗಿ ಕೊನೆಗೊಳ್ಳುತ್ತದೆ';
  }

  @override
  String get dutyBlockedPolicy =>
      'ಕರ್ತವ್ಯಕ್ಕೆ ಹೋಗಲು ಲೊಕೇಶನ್ ನೀತಿಯನ್ನು ಒಪ್ಪಿಕೊಳ್ಳಿ';

  @override
  String get dutyReviewPolicy => 'ನೀತಿ ನೋಡಿ';

  @override
  String dutyPointsPending(int count) {
    return '$count ಪಾಯಿಂಟ್‌ಗಳು ಅಪ್‌ಲೋಡ್‌ಗೆ ಕಾಯುತ್ತಿವೆ';
  }

  @override
  String get dutyNoticeAlreadyActive =>
      'ನೀವು ಈಗಾಗಲೇ ಬೇರೆ ಸಾಧನದಲ್ಲಿ ಕರ್ತವ್ಯದಲ್ಲಿದ್ದೀರಿ. ಇದು ಆಫ್ ಆಗಿಯೇ ಇರುತ್ತದೆ.';

  @override
  String get dutyNoticePolicy =>
      'ಕರ್ತವ್ಯಕ್ಕೆ ಹೋಗುವ ಮೊದಲು ಪ್ರಸ್ತುತ ಲೊಕೇಶನ್ ನೀತಿಯನ್ನು ಒಪ್ಪಿಕೊಳ್ಳಿ.';

  @override
  String get dutyNoticeLocationUnavailable =>
      'ನಿಮ್ಮ ಲೊಕೇಶನ್ ಪಡೆಯಲಾಗಲಿಲ್ಲ. ಲೊಕೇಶನ್ ಆನ್ ಮಾಡಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get integrityBanner =>
      'ಕೆಲವು ಸಾಧನ ಪರಿಶೀಲನೆಗಳು ಸಮಸ್ಯೆ ವರದಿ ಮಾಡಿವೆ; ಭೇಟಿಗಳನ್ನು ಪರಿಶೀಲಿಸಬಹುದು.';

  @override
  String get disclosureIntro =>
      'ಪ್ರಾರಂಭಿಸುವ ಮೊದಲು, ಮಿತ್ರ ಏನನ್ನು ದಾಖಲಿಸುತ್ತದೆ ಮತ್ತು ಏಕೆ ಎಂಬುದು ಇಲ್ಲಿದೆ.';

  @override
  String disclosureVersion(String version) {
    return 'ನೀತಿ ಆವೃತ್ತಿ $version';
  }

  @override
  String get disclosureUpdated =>
      'ಲೊಕೇಶನ್ ನೀತಿ ಬದಲಾಗಿದೆ. ದಯವಿಟ್ಟು ಹೊಸ ಆವೃತ್ತಿಯನ್ನು ಓದಿ ಒಪ್ಪಿಕೊಳ್ಳಿ.';

  @override
  String get policySheetTitle => 'ಲೊಕೇಶನ್ ನೀತಿ';

  @override
  String get locationPolicyText =>
      'ಮಿತ್ರ ಲೊಕೇಶನ್ ನೀತಿ (ಆವೃತ್ತಿ 2026-09-v1)\n\n1. ನಾವು ಏನನ್ನು ಸಂಗ್ರಹಿಸುತ್ತೇವೆ. ನೀವು ಕರ್ತವ್ಯದಲ್ಲಿರುವಾಗ, ಮಿತ್ರ ನಿಮ್ಮ ಲೊಕೇಶನ್ (ಅಕ್ಷಾಂಶ, ರೇಖಾಂಶ, ನಿಖರತೆ, ವೇಗ, ದಿಕ್ಕು), ಸಮಯ, ಬ್ಯಾಟರಿ ಮಟ್ಟ ಮತ್ತು ಮೂಲ ಸಾಧನ ಪರಿಶೀಲನೆಗಳನ್ನು (ಮಾಕ್ ಲೊಕೇಶನ್, ರೂಟ್ ಮಾಡಿದ ಸಾಧನ, ಗಡಿಯಾರ ವ್ಯತ್ಯಾಸ) ದಾಖಲಿಸುತ್ತದೆ. ಭೇಟಿಗಳಲ್ಲಿ ನೀವು ತೆಗೆಯುವ ಫೋಟೋಗಳು, ಟಿಪ್ಪಣಿಗಳು ಮತ್ತು ರೈತರ ದೃಢೀಕರಣಗಳನ್ನೂ ದಾಖಲಿಸುತ್ತದೆ.\n\n2. ಕರ್ತವ್ಯದಲ್ಲಿರುವಾಗ ಮಾತ್ರ. ನೀವು ಕರ್ತವ್ಯ ಆನ್ ಮಾಡಿದ ನಂತರವೇ ಲೊಕೇಶನ್ ದಾಖಲಾಗುತ್ತದೆ; ಕರ್ತವ್ಯ ಆಫ್ ಮಾಡಿದ ಕ್ಷಣ, ಸಂಸ್ಥೆ ನಿಗದಿಪಡಿಸಿದ ಸಮಯಕ್ಕೆ ದಿನ ಮುಗಿದಾಗ (ಡೀಫಾಲ್ಟ್ 20:00) ಅಥವಾ ಮನೆಯ ಬಳಿ 60 ನಿಮಿಷ ನಿಷ್ಕ್ರಿಯವಾಗಿದ್ದಾಗ ನಿಲ್ಲುತ್ತದೆ. ಕರ್ತವ್ಯ ಆಫ್ ಆಗಿರುವಾಗ ಏನೂ ದಾಖಲಾಗುವುದಿಲ್ಲ; ಲೊಕೇಶನ್ ಆನ್ ಇರುವಷ್ಟು ಕಾಲ ಅಧಿಸೂಚನೆ ಯಾವಾಗಲೂ ಕಾಣಿಸುತ್ತದೆ.\n\n3. ಏಕೆ ಸಂಗ್ರಹಿಸುತ್ತೇವೆ. ನಿಮ್ಮ ಟ್ರ್ಯಾಕ್‌ನಿಂದ ಪ್ರಯಾಣ ಭತ್ಯೆಗಾಗಿ ಕಿಲೋಮೀಟರ್‌ಗಳನ್ನು ಲೆಕ್ಕಹಾಕಲಾಗುತ್ತದೆ; ಭೇಟಿಯ ವೇಳೆ ನಿಮ್ಮ ಲೊಕೇಶನ್ ಆ ಭೇಟಿಗೆ ಕ್ರೆಡಿಟ್ ನೀಡುತ್ತದೆ. ಟ್ರ್ಯಾಕ್ ಇಲ್ಲದಿದ್ದರೆ ಸ್ವಯಂಚಾಲಿತ ಪ್ರಯಾಣ ಭತ್ಯೆ ಇಲ್ಲ, ಪರಿಶೀಲಿತ ಭೇಟಿ ಇಲ್ಲ.\n\n4. ಯಾರು ನೋಡಬಹುದು. ನಿಮ್ಮ ಕ್ಲಸ್ಟರ್ ಹೆಡ್, ನಿರ್ದೇಶಕರು ಮತ್ತು ನಿಮ್ಮ ಸಂಸ್ಥೆಯ ಮಾಲೀಕರು ತಮ್ಮ ಪ್ರದೇಶಕ್ಕೆ ನಿಮ್ಮ ಟ್ರ್ಯಾಕ್ ಮತ್ತು ಭೇಟಿಗಳನ್ನು ನೋಡಬಹುದು; ಆಡಿಟರ್‌ಗಳು ಫ್ಲ್ಯಾಗ್ ಮಾಡಿದ ಭೇಟಿಗಳನ್ನು ಪರಿಶೀಲಿಸಬಹುದು. ಸ್ಟೋರ್ ಮ್ಯಾನೇಜರ್‌ಗಳು ಮತ್ತು ರೈತರು ನಿಮ್ಮ ಲೊಕೇಶನ್ ಎಂದಿಗೂ ನೋಡುವುದಿಲ್ಲ. ಕಚ್ಚಾ ಪಾಯಿಂಟ್‌ಗಳನ್ನು 180 ದಿನ ಇರಿಸಿ ನಂತರ ದೈನಂದಿನ ಒಟ್ಟುಗಳಿಗೆ ಕುಗ್ಗಿಸಲಾಗುತ್ತದೆ.';

  @override
  String get permissionsTitle => 'ಮಿತ್ರಕ್ಕೆ ಬೇಕಾದ ಅನುಮತಿಗಳು';

  @override
  String get permissionsIntro =>
      'ಮಿತ್ರ ಇವುಗಳನ್ನು ಒಂದೊಂದಾಗಿ ಕೇಳುತ್ತದೆ. ನಂತರ ಸೆಟ್ಟಿಂಗ್ಸ್‌ನಲ್ಲಿ ಬದಲಾಯಿಸಬಹುದು.';

  @override
  String get permLocationTitle => 'ಲೊಕೇಶನ್';

  @override
  String get permLocationBody =>
      'ಕರ್ತವ್ಯದಲ್ಲಿ ನಿಮ್ಮ ಟ್ರ್ಯಾಕ್ ದಾಖಲಿಸಲು ಮತ್ತು ನೀವು ಹೊಲದಲ್ಲಿದ್ದೀರಾ ಎಂದು ಪರಿಶೀಲಿಸಲು.';

  @override
  String get permBackgroundTitle => 'ಲೊಕೇಶನ್ ಯಾವಾಗಲೂ';

  @override
  String get permBackgroundBody =>
      'ಪರದೆ ಆಫ್ ಆಗಿದ್ದರೂ ಟ್ರ್ಯಾಕಿಂಗ್ ಮುಂದುವರಿಯಲು \"ಯಾವಾಗಲೂ ಅನುಮತಿಸಿ\" ಆಯ್ಕೆಮಾಡಿ. ಆದರೂ ಇದು ಕರ್ತವ್ಯದಲ್ಲಿರುವಾಗ ಮಾತ್ರ ಕೆಲಸ ಮಾಡುತ್ತದೆ.';

  @override
  String get permCameraTitle => 'ಕ್ಯಾಮೆರಾ';

  @override
  String get permCameraBody => 'ಆ್ಯಪ್ ಒಳಗೆ ತೆಗೆಯುವ ಹೊಲ ಮತ್ತು ಭೇಟಿ ಫೋಟೋಗಳಿಗೆ.';

  @override
  String get permNotificationsTitle => 'ಅಧಿಸೂಚನೆಗಳು';

  @override
  String get permNotificationsBody =>
      'ಕರ್ತವ್ಯ ಸೂಚನೆ ತೋರಿಸಲು ಮತ್ತು ಕರ್ತವ್ಯ ಮುಗಿಯುವ ಮೊದಲು ನೆನಪಿಸಲು.';

  @override
  String get permGranted => 'ಅನುಮತಿಸಲಾಗಿದೆ';

  @override
  String get permDenied => 'ಅನುಮತಿಸಿಲ್ಲ';

  @override
  String get permOpenSettings => 'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ';

  @override
  String get permAllow => 'ಅನುಮತಿಸಿ';

  @override
  String get registeredTitle => 'ಸಾಧನ ನೋಂದಣಿಯಾಗಿದೆ';

  @override
  String get registeredBody =>
      'ನೀವು ಸಿದ್ಧ. ದಿನ ಪ್ರಾರಂಭಿಸಲು ಹೋಮ್‌ನಿಂದ ಕರ್ತವ್ಯಕ್ಕೆ ಹೋಗಿ.';

  @override
  String get registeredStart => 'ಹೋಮ್‌ಗೆ ಹೋಗಿ';

  @override
  String get homeTitle => 'ಹೋಮ್';

  @override
  String get homeTodayStats => 'ಇಂದು';

  @override
  String get statVisitsVerified => 'ಪರಿಶೀಲಿತ ಭೇಟಿಗಳು';

  @override
  String get statFarmersAdded => 'ಸೇರಿಸಿದ ರೈತರು';

  @override
  String get statCollections => 'ವಸೂಲಿ';

  @override
  String get homeNextUp => 'ಮುಂದಿನದು';

  @override
  String get homeNextUpEmpty => 'ಇನ್ನೂ ಬೀಟ್ ಯೋಜನೆ ಇಲ್ಲ';

  @override
  String get homeNextUpEmptyHelp =>
      'ನಿಮ್ಮ ಕ್ಲಸ್ಟರ್ ಹೆಡ್ ಹಳ್ಳಿಗಳನ್ನು ನಿಯೋಜಿಸುತ್ತಾರೆ. ಅಲ್ಲಿಯವರೆಗೆ ರೈತರನ್ನು ಸೇರಿಸಿ, ಭೇಟಿಗಳನ್ನು ಪ್ರಾರಂಭಿಸಿ.';

  @override
  String get homeQuickActions => 'ತ್ವರಿತ ಕ್ರಿಯೆಗಳು';

  @override
  String get actionStartVisit => 'ಭೇಟಿ ಪ್ರಾರಂಭಿಸಿ';

  @override
  String get actionScoutCrop => 'ಬೆಳೆ ಪರಿಶೀಲನೆ';

  @override
  String get actionCollectPayment => 'ಪಾವತಿ ಸಂಗ್ರಹಿಸಿ';

  @override
  String get comingSoon => 'ಶೀಘ್ರದಲ್ಲಿ ಬರಲಿದೆ';

  @override
  String get navHome => 'ಹೋಮ್';

  @override
  String get navFarmers => 'ರೈತರು';

  @override
  String get navVisits => 'ಭೇಟಿಗಳು';

  @override
  String get navOrders => 'ಆರ್ಡರ್‌ಗಳು';

  @override
  String get navMe => 'ನಾನು';

  @override
  String get myDayTitle => 'ನನ್ನ ದಿನ';

  @override
  String myDayKm(String km) {
    return 'ಇಂದು $km ಕಿ.ಮೀ';
  }

  @override
  String get myDayEmpty => 'ಇಂದು ಇನ್ನೂ ಕರ್ತವ್ಯ ಇಲ್ಲ';

  @override
  String get myDayEmptyHelp =>
      'ಹೋಮ್‌ನಿಂದ ಕರ್ತವ್ಯಕ್ಕೆ ಹೋಗಿ; ನಿಮ್ಮ ಟ್ರ್ಯಾಕ್ ಮತ್ತು ಕಿ.ಮೀ ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.';

  @override
  String myDaySession(String start, String end) {
    return 'ಕರ್ತವ್ಯ $start – $end';
  }

  @override
  String myDaySessionActive(String start) {
    return '$start ರಿಂದ ಕರ್ತವ್ಯ';
  }

  @override
  String myDayPoints(int pending, int accepted) {
    return '$pending ಬಾಕಿ · $accepted ಸ್ವೀಕೃತ';
  }

  @override
  String get myDayGapsTitle => 'ಅಂತರಗಳು ಮತ್ತು ಕಾರಣಗಳು';

  @override
  String get myDayGapsHelp => 'ಅಂತರದ ಕಾರಣಗಳು ಮುಂದಿನ ಅಪ್‌ಡೇಟ್‌ನೊಂದಿಗೆ ಬರುತ್ತವೆ.';

  @override
  String get myDayEndReasonManual => 'ನೀವು ಮುಗಿಸಿದ್ದೀರಿ';

  @override
  String get myDayEndReasonAutoTime => 'ದಿನದ ಅಂತ್ಯದಲ್ಲಿ ಮುಗಿಯಿತು';

  @override
  String get myDayEndReasonAutoIdle => 'ನಿಷ್ಕ್ರಿಯತೆಯ ನಂತರ ಮುಗಿಯಿತು';

  @override
  String get myDayEndReasonForced => 'ಮ್ಯಾನೇಜರ್ ಮುಗಿಸಿದರು';

  @override
  String get myDayEndReasonRejected => 'ದಾಖಲಾಗಿಲ್ಲ';

  @override
  String get syncEntityDutySession => 'ಕರ್ತವ್ಯ ಅವಧಿ';

  @override
  String get syncEntityLocationBatch => 'ಲೊಕೇಶನ್ ಪಾಯಿಂಟ್‌ಗಳು';

  @override
  String get syncEntityPolicyAcceptance => 'ನೀತಿ ಸ್ವೀಕಾರ';

  @override
  String get visitsTitle => 'ಭೇಟಿಗಳು';

  @override
  String get visitsTabToday => 'ಇಂದು';

  @override
  String get visitsTabWeek => 'ಈ ವಾರ';

  @override
  String get visitsFilterAll => 'ಎಲ್ಲಾ';

  @override
  String get visitsEmptyTitle => 'ಇನ್ನೂ ಭೇಟಿಗಳಿಲ್ಲ';

  @override
  String get visitsEmptyHelp =>
      'ರೈತರ ಪ್ರೊಫೈಲ್‌ನಿಂದ ಅಥವಾ ಕೆಳಗಿನ ಬಟನ್‌ನಿಂದ ಭೇಟಿ ಪ್ರಾರಂಭಿಸಿ.';

  @override
  String get visitStatusOpen => 'ಪ್ರಗತಿಯಲ್ಲಿದೆ';

  @override
  String get visitCardPending => 'ಆನ್‌ಲೈನ್ ಆದಾಗ ಸಿಂಕ್ ಆಗುತ್ತದೆ';

  @override
  String get visitCardFailed => 'ಗಮನ ಅಗತ್ಯ';

  @override
  String get visitChooseFarmer => 'ರೈತರನ್ನು ಆರಿಸಿ';

  @override
  String get visitFarmLabel => 'ಹೊಲ';

  @override
  String get visitFarmNoBoundary => 'ಈ ಹೊಲಕ್ಕೆ ಗಡಿ ದಾಖಲಾಗಿಲ್ಲ';

  @override
  String get visitPurposeLabel => 'ಉದ್ದೇಶ';

  @override
  String get visitOffDutyTitle => 'ಮೊದಲು ಕರ್ತವ್ಯಕ್ಕೆ ಹೋಗಿ';

  @override
  String get visitOffDutyBody =>
      'ನೀವು ಕರ್ತವ್ಯದಲ್ಲಿರುವಾಗ ಮಾತ್ರ ಭೇಟಿಗಳು ದಾಖಲಾಗುತ್ತವೆ. ಹೋಮ್‌ನಿಂದ ಕರ್ತವ್ಯ ಆನ್ ಮಾಡಿ ಹಿಂತಿರುಗಿ.';

  @override
  String get visitGoHome => 'ಹೋಮ್‌ಗೆ ಹೋಗಿ';

  @override
  String get visitLocating => 'ನಿಮ್ಮ ಸ್ಥಳ ಪಡೆಯಲಾಗುತ್ತಿದೆ…';

  @override
  String get visitNoFix =>
      'ನಿಮ್ಮ ಸ್ಥಳ ಸಿಗಲಿಲ್ಲ. ತೆರೆದ ಆಕಾಶದ ಕೆಳಗೆ ಹೋಗಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get visitRefreshLocation => 'ಸ್ಥಳ ಮತ್ತೆ ಪರಿಶೀಲಿಸಿ';

  @override
  String visitAccuracy(int metres) {
    return 'ನಿಖರತೆ ±$metres ಮೀ';
  }

  @override
  String get visitInsideGeofence => 'ನೀವು ಹೊಲದ ಜಿಯೋಫೆನ್ಸ್ ಒಳಗಿದ್ದೀರಿ';

  @override
  String get visitAtMeetingPoint => 'ನೀವು ಗ್ರಾಮದ ಸಭಾ ಸ್ಥಳದಲ್ಲಿದ್ದೀರಿ';

  @override
  String visitOutsideFarm(int distance, int radius) {
    return 'ಹೊಲದ ಗಡಿಯಿಂದ $distance ಮೀ ದೂರ; ಜಿಯೋಫೆನ್ಸ್ $radius ಮೀ.';
  }

  @override
  String visitOutsideMeeting(int distance, int radius) {
    return 'ಸಭಾ ಸ್ಥಳದಿಂದ $distance ಮೀ ದೂರ; ಅನುಮತಿಸಿದ ವ್ಯಾಪ್ತಿ $radius ಮೀ.';
  }

  @override
  String get visitNoTarget =>
      'ಈ ಹೊಲಕ್ಕೆ ಗಡಿ ಇಲ್ಲ ಮತ್ತು ಗ್ರಾಮಕ್ಕೆ ಸಭಾ ಸ್ಥಳ ಇಲ್ಲ. ಓವರ್‌ರೈಡ್ ಟಿಪ್ಪಣಿಯೊಂದಿಗೆ ಚೆಕ್ ಇನ್ ಮಾಡಿ.';

  @override
  String get visitRequestOverride => 'ಓವರ್‌ರೈಡ್ ಕೋರಿ';

  @override
  String get visitOverrideNoteLabel =>
      'ನೀವು ಇಲ್ಲಿಂದ ಏಕೆ ಚೆಕ್ ಇನ್ ಮಾಡುತ್ತಿದ್ದೀರಿ?';

  @override
  String get visitOverrideNoteHint => 'ಉದಾ. ರೈತರನ್ನು ಮಾರುಕಟ್ಟೆಯಲ್ಲಿ ಭೇಟಿಯಾದೆ';

  @override
  String get visitOverrideNoteRequired => 'ಓವರ್‌ರೈಡ್ ಕೋರಲು ಟಿಪ್ಪಣಿ ಸೇರಿಸಿ';

  @override
  String get visitOverrideHelp =>
      'ನಿಮ್ಮ ಕ್ಲಸ್ಟರ್ ಹೆಡ್ ಓವರ್‌ರೈಡ್ ಪರಿಶೀಲಿಸುತ್ತಾರೆ. ಅನುಮೋದಿಸಿದರೆ ಮಾತ್ರ ಭೇಟಿಗೆ ಜಿಯೋಫೆನ್ಸ್ ಕ್ರೆಡಿಟ್ ಸಿಗುತ್ತದೆ.';

  @override
  String get visitCheckIn => 'ಚೆಕ್ ಇನ್';

  @override
  String get visitCheckInOverride => 'ಓವರ್‌ರೈಡ್‌ನೊಂದಿಗೆ ಚೆಕ್ ಇನ್';

  @override
  String get visitInProgress => 'ಭೇಟಿ ಪ್ರಗತಿಯಲ್ಲಿದೆ';

  @override
  String get visitTimerLabel => 'ಭೇಟಿಯ ಸಮಯ';

  @override
  String visitMinDuration(int minutes) {
    return 'ಕನಿಷ್ಠ $minutes ನಿಮಿ';
  }

  @override
  String visitDurationNeeds(int minutes, int minimum) {
    return '$minimum ನಿಮಿಯಲ್ಲಿ $minutes ನಿಮಿ';
  }

  @override
  String visitUnderMinimum(int minutes) {
    return 'ಕನಿಷ್ಠ $minutes ನಿಮಿಗಿಂತ ಕಡಿಮೆ. ಭೇಟಿ ಫ್ಲ್ಯಾಗ್ ಆಗುತ್ತದೆ, ತಿರಸ್ಕೃತವಾಗುವುದಿಲ್ಲ.';
  }

  @override
  String get visitPhotos => 'ಫೋಟೋಗಳು';

  @override
  String get visitTakePhoto => 'ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String visitPhotoCount(int count) {
    return '$count ಫೋಟೋಗಳು';
  }

  @override
  String get visitPhotosHelp =>
      'ಆ್ಯಪ್ ಕ್ಯಾಮೆರಾ ಮಾತ್ರ. ಹೊಲದಲ್ಲಿ ಕನಿಷ್ಠ ಒಂದು ಫೋಟೋ ತೆಗೆಯಿರಿ.';

  @override
  String get visitNotesLabel => 'ಟಿಪ್ಪಣಿಗಳು';

  @override
  String get visitNotesHint => 'ನೀವು ಏನು ಗಮನಿಸಿದಿರಿ ಅಥವಾ ಸಲಹೆ ನೀಡಿದಿರಿ?';

  @override
  String get visitVoiceInputSoon =>
      'ಧ್ವನಿ ಇನ್‌ಪುಟ್ ಮುಂದಿನ ಅಪ್‌ಡೇಟ್‌ನಲ್ಲಿ ಬರುತ್ತದೆ';

  @override
  String get visitCropStageLabel => 'ಬೆಳೆ ಹಂತ';

  @override
  String get cropStageSown => 'ಬಿತ್ತಿದೆ';

  @override
  String get cropStageMaturity => 'ಪಕ್ವತೆ';

  @override
  String get cropStageHarvested => 'ಕಟಾವು ಆಗಿದೆ';

  @override
  String get visitProofTitle => 'ಭೇಟಿಯ ಪುರಾವೆ';

  @override
  String get visitExpectedScore => 'ನಿರೀಕ್ಷಿತ ಸ್ಕೋರ್';

  @override
  String get visitServerScore => 'ಸರ್ವರ್‌ನಿಂದ ಸ್ಕೋರ್';

  @override
  String get visitConfirmFarmer => 'ರೈತರ ದೃಢೀಕರಣ';

  @override
  String get visitCheckOut => 'ಚೆಕ್ ಔಟ್';

  @override
  String get visitCheckInPending => 'ಆನ್‌ಲೈನ್ ಆದಾಗ ಚೆಕ್ ಇನ್ ಸಿಂಕ್ ಆಗುತ್ತದೆ';

  @override
  String get visitCheckInSynced => 'ಚೆಕ್ ಇನ್ ಸಿಂಕ್ ಆಗಿದೆ';

  @override
  String get visitRejectedTitle => 'ಚೆಕ್ ಇನ್ ನಿರಾಕರಿಸಲಾಗಿದೆ';

  @override
  String visitRejectedOutside(int distance) {
    return 'ಸರ್ವರ್ ನಿಮ್ಮನ್ನು ಜಿಯೋಫೆನ್ಸ್‌ನಿಂದ $distance ಮೀ ಹೊರಗೆ ಗುರುತಿಸಿದೆ.';
  }

  @override
  String get visitRejectedNoTarget =>
      'ನಿಮ್ಮ ಸ್ಥಳವನ್ನು ಹೋಲಿಸಲು ಸರ್ವರ್‌ಗೆ ಏನೂ ಸಿಗಲಿಲ್ಲ.';

  @override
  String get visitRetryFromFarm => 'ಹೊಲದಿಂದ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ';

  @override
  String visitRetryStillOutside(int distance) {
    return 'ಇನ್ನೂ $distance ಮೀ ಹೊರಗಿದ್ದೀರಿ. ಹತ್ತಿರ ಹೋಗಿ ಅಥವಾ ಓವರ್‌ರೈಡ್ ಕೋರಿ.';
  }

  @override
  String get visitRetryQueued =>
      'ನಿಮ್ಮ ಪ್ರಸ್ತುತ ಸ್ಥಳದೊಂದಿಗೆ ಚೆಕ್ ಇನ್ ಮತ್ತೆ ಕ್ಯೂನಲ್ಲಿದೆ.';

  @override
  String get proofGeofenceOverride =>
      'ಓವರ್‌ರೈಡ್ ಕೋರಲಾಗಿದೆ; ಕ್ಲಸ್ಟರ್ ಹೆಡ್‌ಗಾಗಿ ಕಾಯುತ್ತಿದೆ';

  @override
  String get proofGeofenceOutside => 'ಜಿಯೋಫೆನ್ಸ್ ಹೊರಗೆ';

  @override
  String get proofPhotoDone => 'ಸ್ಥಳದೊಂದಿಗೆ ಫೋಟೋ ತೆಗೆಯಲಾಗಿದೆ';

  @override
  String get proofDurationDone => 'ಕನಿಷ್ಠ ಅವಧಿ ತಲುಪಿದೆ';

  @override
  String get proofIntegrityIssue =>
      'ಸಾಧನ ಪರಿಶೀಲನೆಗಳಲ್ಲಿ ಸಮಸ್ಯೆ; ಈ ಭಾಗಕ್ಕೆ 0 ಸ್ಕೋರ್';

  @override
  String get visitConfirmTitle => 'ರೈತರ ದೃಢೀಕರಣ';

  @override
  String get visitConfirmIntro =>
      'ಈ ಭೇಟಿಯನ್ನು ದೃಢೀಕರಿಸಲು ರೈತರನ್ನು ಈ ವಿಧಾನಗಳಲ್ಲಿ ಒಂದರ ಮೂಲಕ ಕೇಳಿ.';

  @override
  String get visitConfirmOtp => 'SMS ಮೂಲಕ OTP';

  @override
  String get visitConfirmOtpHelp =>
      'ರೈತರ ಫೋನ್‌ಗೆ ಕೋಡ್ ಹೋಗುತ್ತದೆ; ಅದನ್ನು ಇಲ್ಲಿ ಟೈಪ್ ಮಾಡಿ.';

  @override
  String get visitConfirmPush => 'ಕಿಸಾನ್ ಆ್ಯಪ್‌ನಲ್ಲಿ ಕೇಳಿ';

  @override
  String get visitConfirmPushHelp =>
      'ರೈತರು ತಮ್ಮ ಆ್ಯಪ್‌ನಲ್ಲಿ ದೃಢೀಕರಿಸು ಒತ್ತುತ್ತಾರೆ.';

  @override
  String get visitConfirmQr => 'QR ತೋರಿಸಿ';

  @override
  String get visitConfirmQrHelp =>
      'ರೈತರು ಇದನ್ನು ಕಿಸಾನ್ ಆ್ಯಪ್‌ನಿಂದ ಸ್ಕ್ಯಾನ್ ಮಾಡುತ್ತಾರೆ.';

  @override
  String get visitConfirmNeedsNetwork =>
      'ಇದಕ್ಕೆ ನೆಟ್‌ವರ್ಕ್ ಬೇಕು. ಆನ್‌ಲೈನ್ ಆದಾಗ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get visitConfirmQrNeedsSync =>
      'QR ಗೆ ಮೊದಲು ಒಂದು ಸಿಂಕ್ ಬೇಕು. ಒಮ್ಮೆ ಸಂಪರ್ಕಿಸಿ ಹಿಂತಿರುಗಿ.';

  @override
  String get visitConfirmNotSynced =>
      'ಚೆಕ್ ಇನ್ ಇನ್ನೂ ಸರ್ವರ್ ತಲುಪಿಲ್ಲ. ಸಿಂಕ್ ಮಾಡಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get visitConfirmQueued =>
      'ವಿನಂತಿ ಉಳಿಸಲಾಗಿದೆ. ನೀವು ಆನ್‌ಲೈನ್ ಆದ ಕೂಡಲೇ ರೈತರ ಆ್ಯಪ್‌ಗೆ ಹೋಗುತ್ತದೆ.';

  @override
  String get visitConfirmWaiting => 'ರೈತರಿಗಾಗಿ ಕಾಯುತ್ತಿದ್ದೇವೆ…';

  @override
  String get visitConfirmWaitingPush =>
      'ಕಿಸಾನ್ ಆ್ಯಪ್‌ನಲ್ಲಿ ರೈತರನ್ನು ಕೇಳಿದ್ದೇವೆ. ಅವರು ದೃಢೀಕರಿಸಿದಾಗ ಈ ಪರದೆ ಅಪ್‌ಡೇಟ್ ಆಗುತ್ತದೆ.';

  @override
  String get visitConfirmQrWaiting =>
      'ರೈತರು ಸ್ಕ್ಯಾನ್ ಮಾಡುವವರೆಗೆ ಕಾಯುತ್ತಿದ್ದೇವೆ…';

  @override
  String get visitConfirmed => 'ರೈತರು ದೃಢೀಕರಿಸಿದ್ದಾರೆ';

  @override
  String visitConfirmedVia(String channel) {
    return '$channel ಮೂಲಕ ದೃಢೀಕರಿಸಲಾಗಿದೆ';
  }

  @override
  String visitConfirmOtpSent(String phone) {
    return '$phone ಗೆ ಕೋಡ್ ಕಳುಹಿಸಲಾಗಿದೆ';
  }

  @override
  String get visitConfirmAlready => 'ಈ ಭೇಟಿ ಈಗಾಗಲೇ ದೃಢೀಕರಿಸಲಾಗಿದೆ.';

  @override
  String get visitConfirmRefused =>
      'ಈಗ ರೈತರನ್ನು ಈ ರೀತಿ ಕೇಳಲಾಗದು. ಬೇರೆ ವಿಧಾನ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get visitConfirmContinue => 'ಚೆಕ್ ಔಟ್‌ಗೆ ಮುಂದುವರಿಯಿರಿ';

  @override
  String get visitConfirmLater => 'ನಂತರ ದೃಢೀಕರಿಸಿ';

  @override
  String visitConfirmExpires(int minutes) {
    return '$minutes ನಿಮಿಯಲ್ಲಿ ಅವಧಿ ಮುಗಿಯುತ್ತದೆ';
  }

  @override
  String get visitConfirmChooseAnother => 'ಬೇರೆ ವಿಧಾನ ಆರಿಸಿ';

  @override
  String get visitSummaryTitle => 'ಚೆಕ್ ಔಟ್ ಸಾರಾಂಶ';

  @override
  String get visitSummaryDuration => 'ಅವಧಿ';

  @override
  String get visitSummaryMissing => 'ಏನು ಕೊರತೆಯಿತ್ತು';

  @override
  String get visitSummaryComplete => 'ಎಲ್ಲವೂ ಸರಿಯಾಗಿದೆ';

  @override
  String get visitSummaryPending =>
      'ಮುಂದಿನ ಸಿಂಕ್ ನಂತರ ಸರ್ವರ್ ಸ್ಕೋರ್ ದೃಢೀಕರಿಸುತ್ತದೆ';

  @override
  String get visitSummaryServer => 'ಸರ್ವರ್ ಸ್ಕೋರ್ ದೃಢೀಕರಿಸಿದೆ';

  @override
  String get visitSummaryNotCheckedOut => 'ಈ ಭೇಟಿ ಇನ್ನೂ ತೆರೆದಿದೆ.';

  @override
  String get visitSummaryOverridePending => 'ಓವರ್‌ರೈಡ್ ಪರಿಶೀಲನೆಗಾಗಿ ಕಾಯುತ್ತಿದೆ';

  @override
  String get visitDone => 'ಮುಗಿದಿದೆ';

  @override
  String get syncEntityVisit => 'ಭೇಟಿ';

  @override
  String get syncEntityVisitPhoto => 'ಭೇಟಿ ಫೋಟೋ';

  @override
  String get syncEntityVisitConfirmation => 'ರೈತರ ದೃಢೀಕರಣ';

  @override
  String get catalogTitle => 'ಉತ್ಪನ್ನಗಳು';

  @override
  String catalogForFarmer(String name) {
    return '$name ಅವರಿಗಾಗಿ';
  }

  @override
  String get catalogSearchHint => 'ಹೆಸರು, ಬ್ರಾಂಡ್ ಅಥವಾ ಘಟಕ ಹುಡುಕಿ';

  @override
  String get catalogCategoryAll => 'ಎಲ್ಲಾ';

  @override
  String get catalogCategorySeed => 'ಬೀಜಗಳು';

  @override
  String get catalogCategoryFertiliser => 'ರಸಗೊಬ್ಬರಗಳು';

  @override
  String get catalogCategoryPesticide => 'ಕೀಟನಾಶಕಗಳು';

  @override
  String get catalogCategoryFungicide => 'ಶಿಲೀಂಧ್ರನಾಶಕಗಳು';

  @override
  String get catalogCategoryHerbicide => 'ಕಳೆನಾಶಕಗಳು';

  @override
  String get catalogCategoryGrowth => 'ಬೆಳವಣಿಗೆ ವರ್ಧಕಗಳು';

  @override
  String get catalogCategoryTool => 'ಉಪಕರಣಗಳು';

  @override
  String get catalogCategoryOther => 'ಇತರೆ';

  @override
  String catalogAsOf(String time) {
    return '$time ರ ಬೆಲೆ ಮತ್ತು ದಾಸ್ತಾನು';
  }

  @override
  String catalogStale(String time) {
    return 'ಬೆಲೆ ಮತ್ತು ದಾಸ್ತಾನು ಹಳೆಯದಿರಬಹುದು ($time ರದು). ಇಂಟರ್ನೆಟ್ ಇದ್ದಾಗ ರಿಫ್ರೆಶ್ ಮಾಡಿ.';
  }

  @override
  String get catalogNeverLoaded => 'ಉತ್ಪನ್ನ ಪಟ್ಟಿ ಇನ್ನೂ ಈ ಫೋನ್‌ನಲ್ಲಿ ಇಲ್ಲ';

  @override
  String get catalogNeverLoadedHelp =>
      'ಉತ್ಪನ್ನಗಳು ಮತ್ತು ಬೆಲೆ ಡೌನ್‌ಲೋಡ್ ಮಾಡಲು ಇಂಟರ್ನೆಟ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ.';

  @override
  String get catalogRefresh => 'ರಿಫ್ರೆಶ್ ಮಾಡಿ';

  @override
  String get catalogRefreshFailed =>
      'ರಿಫ್ರೆಶ್ ಆಗಲಿಲ್ಲ. ಉಳಿಸಿದ ಉತ್ಪನ್ನಗಳನ್ನು ತೋರಿಸಲಾಗುತ್ತಿದೆ.';

  @override
  String get catalogEmpty => 'ಹೊಂದುವ ಉತ್ಪನ್ನಗಳಿಲ್ಲ';

  @override
  String get catalogEmptyHelp => 'ಬೇರೆ ಹೆಸರು ಅಥವಾ ವರ್ಗ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get catalogStoreUnknown =>
      'ಅಂಗಡಿ ಇನ್ನೂ ತಿಳಿದಿಲ್ಲ. ಮುಂದಿನ ಸಿಂಕ್ ನಂತರ ದಾಸ್ತಾನು ಕಾಣುತ್ತದೆ.';

  @override
  String get productPriceEstimate => 'ಅಂದಾಜು ಬೆಲೆ';

  @override
  String productStockNearest(int count) {
    return 'ಹತ್ತಿರದ ಅಂಗಡಿಯಲ್ಲಿ $count ದಾಸ್ತಾನಿನಲ್ಲಿವೆ';
  }

  @override
  String productStockAsOf(String time) {
    return '$time ಕ್ಕೆ';
  }

  @override
  String productInCart(int count) {
    return 'ಕಾರ್ಟ್‌ನಲ್ಲಿ $count';
  }

  @override
  String get cartEstimatedTotal => 'ಅಂದಾಜು ಒಟ್ಟು';

  @override
  String get cartViewCart => 'ಕಾರ್ಟ್ ನೋಡಿ';

  @override
  String get cartTitle => 'ಕಾರ್ಟ್';

  @override
  String get cartEmpty => 'ಕಾರ್ಟ್ ಖಾಲಿಯಾಗಿದೆ';

  @override
  String get cartEmptyHelp => 'ಪಟ್ಟಿಯಿಂದ ಉತ್ಪನ್ನಗಳನ್ನು ಸೇರಿಸಿ.';

  @override
  String get cartAddMore => 'ಇನ್ನಷ್ಟು ಉತ್ಪನ್ನ ಸೇರಿಸಿ';

  @override
  String get cartSubtotal => 'ಉಪ ಮೊತ್ತ (ಅಂದಾಜು)';

  @override
  String get cartTax => 'GST (ಅಂದಾಜು)';

  @override
  String get cartEstimateNote =>
      'ಬೆಲೆಗಳು ಉಳಿಸಿದ ಬೆಲೆ ಪಟ್ಟಿಯ ಅಂದಾಜು. ಆರ್ಡರ್ ಸಿಂಕ್ ಆದಾಗ ಅಂಗಡಿ ಅಂತಿಮ ಮೊತ್ತ ಖಚಿತಪಡಿಸುತ್ತದೆ.';

  @override
  String get cartFulfilment => 'ರೈತರಿಗೆ ಸರಕು ಹೇಗೆ ತಲುಪುತ್ತದೆ?';

  @override
  String get fulfilmentPickup => 'ಅಂಗಡಿಯಿಂದ ಪಡೆಯುವುದು';

  @override
  String get fulfilmentDelivery => 'ಮನೆಗೆ ಡೆಲಿವರಿ';

  @override
  String get cartChoosePayment => 'ಪಾವತಿ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get cartDecrease => 'ಒಂದು ಕಡಿಮೆ ಮಾಡಿ';

  @override
  String get cartIncrease => 'ಒಂದು ಹೆಚ್ಚಿಸಿ';

  @override
  String cartShortLine(String available, String requested) {
    return 'ಅಂಗಡಿಯಲ್ಲಿ $available ಮಾತ್ರ ಲಭ್ಯ ($requested ಕೇಳಲಾಗಿದೆ).';
  }

  @override
  String cartUseAvailable(String available) {
    return '$available ಇಡಿ';
  }

  @override
  String get cartShortTitle =>
      'ಅಂಗಡಿಯಲ್ಲಿ ಕೆಲವು ಸರಕು ಕಡಿಮೆ ಇದೆ. ಪ್ರಮಾಣ ಬದಲಿಸಿ ಮತ್ತೆ ಕಳುಹಿಸಿ.';

  @override
  String get checkoutTitle => 'ಪಾವತಿ';

  @override
  String get checkoutOrderAmount => 'ಆರ್ಡರ್ ಒಟ್ಟು (ಅಂದಾಜು)';

  @override
  String get checkoutDuesAmount => 'ವಸೂಲಿ ಮಾಡಬೇಕಾದ ಮೊತ್ತ (₹)';

  @override
  String checkoutDuesBalance(String amount) {
    return 'ಬಾಕಿ $amount';
  }

  @override
  String checkoutDuesTooMuch(String amount) {
    return '$amount ವರೆಗಿನ ಮೊತ್ತ ನಮೂದಿಸಿ';
  }

  @override
  String get checkoutDuesInvalid => 'ಮೊತ್ತ ನಮೂದಿಸಿ';

  @override
  String get checkoutPlaceOrder => 'ಆರ್ಡರ್ ಮಾಡಿ';

  @override
  String get checkoutCollect => 'ವಸೂಲಿ ಮಾಡಿ';

  @override
  String get checkoutNeedsInternet => 'ಇಂಟರ್ನೆಟ್ ಬೇಕು: ನಗದು ಅಥವಾ ಸಾಲ ಬಳಸಿ';

  @override
  String get checkoutCreditOrdersOnly => 'ಸಾಲ ಆರ್ಡರ್‌ಗಳಿಗೆ ಮಾತ್ರ';

  @override
  String checkoutCreditLeft(String amount) {
    return 'ಉಳಿದ ಮಿತಿ $amount';
  }

  @override
  String get checkoutOfflineNote =>
      'ನೀವು ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿದ್ದೀರಿ. ನಗದು ಮತ್ತು ಸಾಲ ಫೋನ್‌ನಲ್ಲಿ ಉಳಿದು ಇಂಟರ್ನೆಟ್ ಬಂದಾಗ ಕಳುಹಿಸಲಾಗುತ್ತದೆ.';

  @override
  String get checkoutOrderNotSynced =>
      'ಆರ್ಡರ್ ಇನ್ನೂ ಸರ್ವರ್ ತಲುಪಿಲ್ಲ. ಇಂಟರ್ನೆಟ್ ಇದ್ದಾಗ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ ಅಥವಾ ನಗದು ಪಡೆಯಿರಿ.';

  @override
  String get checkoutNetworkError =>
      'ಸರ್ವರ್ ತಲುಪಲಾಗಲಿಲ್ಲ. ಇಂಟರ್ನೆಟ್ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get checkoutAlreadyPaid => 'ಈ ಆರ್ಡರ್‌ಗೆ ಈಗಾಗಲೇ ಪಾವತಿಯಾಗಿದೆ.';

  @override
  String get checkoutAmountMismatch =>
      'ಸರ್ವರ್‌ನಲ್ಲಿ ಮೊತ್ತ ಬದಲಾಗಿದೆ. ಆರ್ಡರ್ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get checkoutNothingDue => 'ಈ ರೈತರ ಬಾಕಿ ಏನೂ ಇಲ್ಲ.';

  @override
  String checkoutRefused(String code) {
    return 'ಪಾವತಿ ರಚಿಸಲಾಗಲಿಲ್ಲ ($code).';
  }

  @override
  String get paymentCard => 'ಕಾರ್ಡ್';

  @override
  String get paymentDone => 'ಮುಗಿಯಿತು';

  @override
  String get upiTitle => 'UPI QR';

  @override
  String get upiExpired => 'QR ಅವಧಿ ಮುಗಿದಿದೆ';

  @override
  String get upiCollectCash => 'ಬದಲಿಗೆ ನಗದು ಪಡೆಯಿರಿ';

  @override
  String get linkTitle => 'ಪಾವತಿ ಲಿಂಕ್';

  @override
  String get linkSentTitle => 'ಪಾವತಿ ಲಿಂಕ್ ಕಳುಹಿಸಲಾಗಿದೆ';

  @override
  String linkSentVia(String channel) {
    return '$channel ಮೂಲಕ ಕಳುಹಿಸಲಾಗಿದೆ. ಲಿಂಕ್ ತೆರೆದು ಪಾವತಿಸಲು ರೈತರಿಗೆ ಹೇಳಿ.';
  }

  @override
  String get channelSms => 'SMS';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get linkResend => 'ಲಿಂಕ್ ಮತ್ತೆ ಕಳುಹಿಸಿ';

  @override
  String get linkResent => 'ಲಿಂಕ್ ಮತ್ತೆ ಕಳುಹಿಸಲಾಗಿದೆ';

  @override
  String get linkCheckStatus => 'ಪಾವತಿ ಪರಿಶೀಲಿಸಿ';

  @override
  String linkValidUntil(String time) {
    return '$time ವರೆಗೆ ಮಾನ್ಯ';
  }

  @override
  String get cashTitle => 'ನಗದು ರಸೀದಿ';

  @override
  String get cashAmount => 'ಪಡೆದ ನಗದು';

  @override
  String get cashTakePhoto => 'ರಸೀದಿ ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get cashRetake => 'ಮತ್ತೆ ತೆಗೆಯಿರಿ';

  @override
  String get cashSave => 'ನಗದು ಪಾವತಿ ಉಳಿಸಿ';

  @override
  String get cashPhotoHelp =>
      'ರೈತರಿಗೆ ನೀಡಿದ ರಸೀದಿಯ ಫೋಟೋ ತೆಗೆಯಿರಿ. ಆ್ಯಪ್ ಕ್ಯಾಮೆರಾ ಮಾತ್ರ ಬಳಸಬಹುದು.';

  @override
  String get cashPhotoBad =>
      'ಫೋಟೋ ಮಸುಕು ಅಥವಾ ಕತ್ತಲಾಗಿದೆ. ಉತ್ತಮ ಬೆಳಕಿನಲ್ಲಿ ಮತ್ತೆ ತೆಗೆಯಿರಿ.';

  @override
  String get cashSaved => 'ನಗದು ಉಳಿಸಲಾಗಿದೆ. ಅಂಗಡಿ ಹೊಂದಾಣಿಕೆ ಬಾಕಿ ಇದೆ.';

  @override
  String get cashPendingReconciliation =>
      'ಅಂಗಡಿ ಹೊಂದಾಣಿಕೆ ಬಾಕಿ: ದಿನದ ಕೊನೆಯಲ್ಲಿ ಅಂಗಡಿ ನಗದು ಪರಿಶೀಲಿಸುತ್ತದೆ.';

  @override
  String get creditTitle => 'ಸಾಲದ ಮಾರಾಟ';

  @override
  String get creditQueued =>
      'ಫೋನ್‌ನಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ. ಇಂಟರ್ನೆಟ್ ಬಂದಾಗ ಸಾಲದ ಮಿತಿ ಪರಿಶೀಲಿಸಲಾಗುತ್ತದೆ.';

  @override
  String get creditApprovedTitle => 'ರೈತರ ಖಾತೆಗೆ ಸೇರಿಸಲಾಗಿದೆ';

  @override
  String get creditNeedsApprovalTitle => 'ಅನುಮೋದನೆ ಬೇಕು';

  @override
  String get creditNeedsApprovalBody =>
      'ಈ ಮಾರಾಟ ರೈತರ ಸಾಲದ ಮಿತಿ ಮೀರಿದೆ. ಅನುಮೋದನೆಗಾಗಿ ಕ್ಲಸ್ಟರ್ ಹೆಡ್‌ಗೆ ಕಳುಹಿಸಲಾಗಿದೆ.';

  @override
  String get creditLimit => 'ಸಾಲದ ಮಿತಿ';

  @override
  String get creditBalance => 'ಈಗಿನ ಬಾಕಿ';

  @override
  String get creditShortfall => 'ಮಿತಿ ಮೀರಿದ ಮೊತ್ತ';

  @override
  String get creditSentToClusterHead => 'ಕ್ಲಸ್ಟರ್ ಹೆಡ್‌ಗೆ ಕಳುಹಿಸಲಾಗಿದೆ';

  @override
  String get creditCheckAgain => 'ಅನುಮೋದನೆ ಪರಿಶೀಲಿಸಿ';

  @override
  String get creditStillPending =>
      'ಇನ್ನೂ ಅನುಮೋದನೆ ಸಿಕ್ಕಿಲ್ಲ. ನಂತರ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get creditOfflineCheck =>
      'ಅನುಮೋದನೆ ಪರಿಶೀಲಿಸಲು ಇಂಟರ್ನೆಟ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ.';

  @override
  String get creditUseCash => 'ಬದಲಿಗೆ ನಗದು ಪಡೆಯಿರಿ';

  @override
  String get orderTitle => 'ಆರ್ಡರ್';

  @override
  String get orderPlacedTitle => 'ಆರ್ಡರ್ ಮಾಡಲಾಗಿದೆ';

  @override
  String get orderQueuedTitle => 'ಆರ್ಡರ್ ಉಳಿಸಲಾಗಿದೆ, ಸಿಂಕ್‌ಗಾಗಿ ಕಾಯುತ್ತಿದೆ';

  @override
  String get orderQueuedHelp =>
      'ಫೋನ್‌ಗೆ ಇಂಟರ್ನೆಟ್ ಬಂದ ತಕ್ಷಣ ಇದು ಅಂಗಡಿಗೆ ಹೋಗುತ್ತದೆ.';

  @override
  String get orderRejectedTitle => 'ಅಂಗಡಿ ಈ ಆರ್ಡರ್ ತೆಗೆದುಕೊಳ್ಳಲಾಗಲಿಲ್ಲ';

  @override
  String get orderInsufficientStock => 'ಅಂಗಡಿಯಲ್ಲಿ ಕೆಲವು ಸರಕು ಕಡಿಮೆ:';

  @override
  String orderShortLine(String product, String available, String requested) {
    return '$product: $available ಲಭ್ಯ, $requested ಕೇಳಲಾಗಿದೆ';
  }

  @override
  String get orderSkuNotRecommendable =>
      'ಒಂದು ಉತ್ಪನ್ನಕ್ಕೆ ಈ ಬೆಳೆ ಮತ್ತು ಕೀಟಕ್ಕೆ ಅನುಮೋದನೆ ಇಲ್ಲ (ಲೇಬಲ್ ಕ್ಲೇಮ್). ಅದನ್ನು ತೆಗೆದು ಮತ್ತೆ ಕಳುಹಿಸಿ.';

  @override
  String get orderEditAndResend => 'ಬದಲಿಸಿ ಮತ್ತೆ ಕಳುಹಿಸಿ';

  @override
  String get orderSummary => 'ಸಾರಾಂಶ';

  @override
  String get orderSubtotal => 'ಉಪ ಮೊತ್ತ';

  @override
  String get orderTax => 'GST';

  @override
  String get orderTotal => 'ಒಟ್ಟು';

  @override
  String get orderTotalEstimate => 'ಒಟ್ಟು (ಅಂದಾಜು)';

  @override
  String get orderStatusTitle => 'ಸ್ಥಿತಿ';

  @override
  String get orderStatusPlaced => 'ಆರ್ಡರ್ ಆಗಿದೆ';

  @override
  String get orderStatusReserved => 'ದಾಸ್ತಾನು ಕಾಯ್ದಿರಿಸಲಾಗಿದೆ';

  @override
  String get orderStatusPacked => 'ಪ್ಯಾಕ್ ಆಗಿದೆ';

  @override
  String get orderStatusReady => 'ಸಿದ್ಧ';

  @override
  String get orderStatusHandedOver => 'ಹಸ್ತಾಂತರಿಸಲಾಗಿದೆ';

  @override
  String get orderStatusDelivered => 'ತಲುಪಿಸಲಾಗಿದೆ';

  @override
  String get orderStatusCancelled => 'ರದ್ದಾಗಿದೆ';

  @override
  String get orderPayments => 'ಪಾವತಿಗಳು';

  @override
  String get orderNoPayments => 'ಇನ್ನೂ ಪಾವತಿ ಇಲ್ಲ';

  @override
  String get orderShareInvoice => 'WhatsAppನಲ್ಲಿ ಬಿಲ್ ಹಂಚಿಕೊಳ್ಳಿ';

  @override
  String get orderShareOffline => 'ಬಿಲ್ ಹಂಚಿಕೊಳ್ಳಲು ಇಂಟರ್ನೆಟ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ.';

  @override
  String get orderShareNoInvoice =>
      'ಅಂಗಡಿ ಆರ್ಡರ್ ಹಸ್ತಾಂತರಿಸುವಾಗ ಬಿಲ್ ನೀಡುತ್ತದೆ.';

  @override
  String get orderShareFailed => 'ಬಿಲ್ ಲಿಂಕ್ ಸಿಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String orderShareText(String number, String url) {
    return 'ಬಿಲ್ $number: $url';
  }

  @override
  String orderInvoiceNo(String number) {
    return 'ಬಿಲ್ $number';
  }

  @override
  String get orderCollectPayment => 'ಪಾವತಿ ಪಡೆಯಿರಿ';

  @override
  String get orderPendingSync => 'ಸಿಂಕ್‌ಗಾಗಿ ಕಾಯುತ್ತಿದೆ';

  @override
  String get orderRejected => 'ಗಮನಿಸಬೇಕು';

  @override
  String get ordersTitle => 'ಆರ್ಡರ್‌ಗಳು';

  @override
  String get ordersEmpty => 'ಇನ್ನೂ ಆರ್ಡರ್‌ಗಳಿಲ್ಲ';

  @override
  String get ordersEmptyHelp =>
      'ರೈತರಿಗಾಗಿ ನೀವು ಮಾಡಿದ ಆರ್ಡರ್‌ಗಳು ಇಲ್ಲಿ ಕಾಣುತ್ತವೆ.';

  @override
  String get ordersNew => 'ಹೊಸ ಆರ್ಡರ್';

  @override
  String get ordersCollections => 'ವಸೂಲಿಗಳು';

  @override
  String get ordersPickFarmer => 'ರೈತರನ್ನು ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get khataTitle => 'ಖಾತೆ';

  @override
  String khataAsOf(String time) {
    return '$time ಕ್ಕೆ';
  }

  @override
  String khataOfflineAsOf(String time) {
    return 'ಆಫ್‌ಲೈನ್: $time ರಂದು ಉಳಿಸಿದ ಖಾತೆ ತೋರಿಸಲಾಗುತ್ತಿದೆ';
  }

  @override
  String get khataNotLoaded => 'ಖಾತೆ ಇನ್ನೂ ಈ ಫೋನ್‌ನಲ್ಲಿ ಇಲ್ಲ';

  @override
  String get khataNotLoadedHelp => 'ರೈತರ ಖಾತೆ ತರಲು ಇಂಟರ್ನೆಟ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ.';

  @override
  String khataOverdue(String amount) {
    return 'ಅವಧಿ ಮೀರಿದ ಬಾಕಿ $amount';
  }

  @override
  String get khataBucket0to30 => '0–30 ದಿನ';

  @override
  String get khataBucket31to60 => '31–60 ದಿನ';

  @override
  String get khataBucket61to90 => '61–90 ದಿನ';

  @override
  String get khataBucket90plus => '90+ ದಿನ';

  @override
  String khataDueHarvest(String date, String month) {
    return 'ಬಾಕಿ ದಿನಾಂಕ $date · ಕೊಯ್ಲು $month';
  }

  @override
  String get khataEntryOrder => 'ಸಾಲದ ಮಾರಾಟ';

  @override
  String get khataEntryPayment => 'ಪಾವತಿ ಸ್ವೀಕರಿಸಲಾಗಿದೆ';

  @override
  String get khataEntryAdjustment => 'ಹೊಂದಾಣಿಕೆ';

  @override
  String get khataPaymentHistory => 'ಪಾವತಿ ಇತಿಹಾಸ';

  @override
  String get khataNoPayments => 'ಇನ್ನೂ ಪಾವತಿಗಳಿಲ್ಲ';

  @override
  String get khataPendingCollections => 'ವಸೂಲಿಯಾಗಿದೆ, ಇನ್ನೂ ಖಾತೆಯಲ್ಲಿ ಇಲ್ಲ';

  @override
  String get collectionsTitle => 'ವಸೂಲಿಗಳು';

  @override
  String get collectionsToday => 'ಇಂದು';

  @override
  String get collectionsWeek => 'ಈ ವಾರ';

  @override
  String get collectionsTotal => 'ಒಟ್ಟು ವಸೂಲಿ';

  @override
  String get collectionsEmpty => 'ಇನ್ನೂ ವಸೂಲಿ ಇಲ್ಲ';

  @override
  String get collectionsEmptyHelp =>
      'ನೀವು ವಸೂಲಿ ಮಾಡಿದ ಪಾವತಿಗಳು ಇಲ್ಲಿ ಕಾಣುತ್ತವೆ.';

  @override
  String get collectionStateWaitingToSync => 'ಸಿಂಕ್‌ಗಾಗಿ ಕಾಯುತ್ತಿದೆ';

  @override
  String get collectionStatePendingReconciliation => 'ಹೊಂದಾಣಿಕೆ ಬಾಕಿ';

  @override
  String get collectionStateWaiting => 'ಪಾವತಿಗಾಗಿ ಕಾಯುತ್ತಿದೆ';

  @override
  String get collectionStatePaid => 'ಪಾವತಿಯಾಗಿದೆ';

  @override
  String get collectionStateOnKhata => 'ಖಾತೆಯಲ್ಲಿ';

  @override
  String get collectionStateApprovalNeeded => 'ಅನುಮೋದನೆ ಬೇಕು';

  @override
  String get collectionStateFailed => 'ವಿಫಲವಾಗಿದೆ';

  @override
  String get syncEntityOrder => 'ಆರ್ಡರ್';

  @override
  String get syncEntityPayment => 'ಪಾವತಿ';

  @override
  String get storeModeTitle => 'ಸ್ಟೋರ್ ಮೋಡ್';

  @override
  String get storeSettingsEntryHint =>
      'ಮಾರಾಟ, ಆರ್ಡರ್‌ಗಳು, ಸ್ಟಾಕ್ ಮತ್ತು ದಿನದ ಮುಕ್ತಾಯ';

  @override
  String get storeNavHome => 'ಮುಖಪುಟ';

  @override
  String get storeNavPos => 'ಮಾರಾಟ';

  @override
  String get storeNavQueue => 'ಆರ್ಡರ್‌ಗಳು';

  @override
  String get storeNavStock => 'ಸ್ಟಾಕ್';

  @override
  String get storeNavCredit => 'ಸಾಲ';

  @override
  String get storeNavDayClose => 'ದಿನದ ಮುಕ್ತಾಯ';

  @override
  String get storeReadOnlyBanner =>
      'ನೀವು ಈ ಸ್ಟೋರ್ ಅನ್ನು ನೋಡುತ್ತಿದ್ದೀರಿ. ಬದಲಾವಣೆಗಳನ್ನು ಸ್ಟೋರ್ ತಂಡ ಮಾತ್ರ ಮಾಡಬಹುದು.';

  @override
  String get storeNotAllowedTitle => 'ಸ್ಟೋರ್ ಮೋಡ್ ಲಭ್ಯವಿಲ್ಲ';

  @override
  String get storeNotAllowedHelp =>
      'ಸ್ಟೋರ್ ಮೋಡ್ ಸ್ಟೋರ್ ಮ್ಯಾನೇಜರ್‌ಗಳು, ಲೆಕ್ಕಿಗರು ಮತ್ತು ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರಿಗಾಗಿ.';

  @override
  String get storeOfflineTitle => 'ನೀವು ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿದ್ದೀರಿ';

  @override
  String get storeOfflineHelp =>
      'ಸ್ಟೋರ್ ಮೋಡ್‌ಗೆ ನೆಟ್‌ವರ್ಕ್ ಬೇಕು. ಸಂಪರ್ಕ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get storeErrorTitle => 'ಲೋಡ್ ಆಗಲಿಲ್ಲ';

  @override
  String get storeErrorHelp => 'ಏನೋ ತಪ್ಪಾಗಿದೆ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get storeSwitchStore => 'ಸ್ಟೋರ್ ಬದಲಿಸಿ';

  @override
  String get storeHomeTitle => 'ಸ್ಟೋರ್ ಮುಖಪುಟ';

  @override
  String get storeTodaySales => 'ಇಂದಿನ ಮಾರಾಟ';

  @override
  String storeSalesCount(int count) {
    return 'ಪಾವತಿಗಳು: $count';
  }

  @override
  String get storeModeUpi => 'UPI QR';

  @override
  String get storeModeCard => 'ಕಾರ್ಡ್';

  @override
  String get storeModeCash => 'ನಗದು';

  @override
  String get storeModeCredit => 'ಸಾಲ (ಖಾತೆ)';

  @override
  String get storeQueueCounts => 'ಆರ್ಡರ್ ಸರದಿ';

  @override
  String get storeTabNew => 'ಹೊಸದು';

  @override
  String get storeTabPacking => 'ಪ್ಯಾಕಿಂಗ್';

  @override
  String get storeTabReady => 'ಸಿದ್ಧ';

  @override
  String get storeTabHandedOver => 'ಹಸ್ತಾಂತರಿಸಲಾಗಿದೆ';

  @override
  String storeTabWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get storeLowStock => 'ಕಡಿಮೆ ಸ್ಟಾಕ್';

  @override
  String storeLowStockCount(int count) {
    return 'ಕಡಿಮೆ ಇರುವ ವಸ್ತುಗಳು: $count';
  }

  @override
  String storeExpiringCount(int count) {
    return 'ಶೀಘ್ರದಲ್ಲಿ ಅವಧಿ ಮುಗಿಯುವವು: $count';
  }

  @override
  String get storeDayCloseStatus => 'ದಿನದ ಮುಕ್ತಾಯ';

  @override
  String get storeDayOpen => 'ತೆರೆದಿದೆ, ಇನ್ನೂ ಮುಚ್ಚಿಲ್ಲ';

  @override
  String storeDayClosed(String time) {
    return '$timeಕ್ಕೆ ಮುಚ್ಚಲಾಗಿದೆ';
  }

  @override
  String get storeDayReopened => 'ಮತ್ತೆ ತೆರೆಯಲಾಗಿದೆ';

  @override
  String get storeActionNewSale => 'ಹೊಸ ಮಾರಾಟ';

  @override
  String get storeActionReceive => 'ಸರಕು ಸ್ವೀಕಾರ';

  @override
  String get storeActionTransfer => 'ಸ್ಟಾಕ್ ವರ್ಗಾವಣೆ';

  @override
  String get storeActionCloseDay => 'ದಿನ ಮುಗಿಸಿ';

  @override
  String get storePosTitle => 'ಮಾರಾಟ ಕೌಂಟರ್';

  @override
  String get storeSearchProducts => 'ಉತ್ಪನ್ನಗಳನ್ನು ಹುಡುಕಿ';

  @override
  String get storeScan => 'ಸ್ಕ್ಯಾನ್';

  @override
  String get storeEnterCode => 'ಕೋಡ್ ನಮೂದಿಸಿ';

  @override
  String get storeCodeHint => 'ಬಾರ್‌ಕೋಡ್ ಸಂಖ್ಯೆ';

  @override
  String get storeCodeAdd => 'ಸೇರಿಸಿ';

  @override
  String storeScanAdded(String name) {
    return '$name ಸೇರಿಸಲಾಗಿದೆ';
  }

  @override
  String storeScanNotFound(String code) {
    return '$code ಕೋಡ್‌ನ ಉತ್ಪನ್ನ ಇಲ್ಲ';
  }

  @override
  String get storeScanOffline => 'ಆಫ್‌ಲೈನ್: ಕೋಡ್ ಹುಡುಕಲು ಆಗುವುದಿಲ್ಲ';

  @override
  String get storeCategoryAll => 'ಎಲ್ಲಾ';

  @override
  String get storeCategorySeed => 'ಬೀಜಗಳು';

  @override
  String get storeCategoryFertiliser => 'ರಸಗೊಬ್ಬರಗಳು';

  @override
  String get storeCategoryPesticide => 'ಕೀಟನಾಶಕಗಳು';

  @override
  String get storeCategoryFungicide => 'ಶಿಲೀಂಧ್ರನಾಶಕಗಳು';

  @override
  String get storeCategoryHerbicide => 'ಕಳೆನಾಶಕಗಳು';

  @override
  String get storeCategoryGrowth => 'ಬೆಳವಣಿಗೆ ಪ್ರವರ್ಧಕಗಳು';

  @override
  String get storeCategoryTool => 'ಉಪಕರಣಗಳು';

  @override
  String get storeCategoryOther => 'ಇತರೆ';

  @override
  String get storeCartTitle => 'ಕಾರ್ಟ್';

  @override
  String get storeCartEmpty => 'ಕಾರ್ಟ್ ಖಾಲಿಯಾಗಿದೆ';

  @override
  String get storeCartEmptyHelp =>
      'ಸೇರಿಸಲು ಬಾರ್‌ಕೋಡ್ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ ಅಥವಾ ಉತ್ಪನ್ನವನ್ನು ಒತ್ತಿ.';

  @override
  String get storeQtyDecrease => 'ಕಡಿಮೆ ಮಾಡಿ';

  @override
  String get storeQtyIncrease => 'ಹೆಚ್ಚಿಸಿ';

  @override
  String get storeSubtotal => 'ಉಪ ಮೊತ್ತ (GST ಮೊದಲು)';

  @override
  String get storeGst => 'GST';

  @override
  String get storeTotal => 'ಒಟ್ಟು';

  @override
  String get storeRoundOff => 'ರೌಂಡ್ ಆಫ್';

  @override
  String get storeBuyerPhone => 'ರೈತರ ಫೋನ್';

  @override
  String get storeBuyerFind => 'ಹುಡುಕಿ';

  @override
  String get storeBuyerWalkIn => 'ನೇರ ಗ್ರಾಹಕರಾದರೆ ಖಾಲಿ ಬಿಡಿ';

  @override
  String get storeBuyerUnknown =>
      'ಹೊಸ ಸಂಖ್ಯೆ: ಮಾರಾಟ ಈ ಫೋನ್ ಹೆಸರಿನಲ್ಲಿ ದಾಖಲಾಗುತ್ತದೆ';

  @override
  String get storeBuyerClear => 'ತೆಗೆದುಹಾಕಿ';

  @override
  String get storeNoProducts => 'ಹೊಂದುವ ಉತ್ಪನ್ನಗಳಿಲ್ಲ';

  @override
  String get storeCheckoutTitle => 'ಪಾವತಿ';

  @override
  String get storePayWith => 'ಪಾವತಿ ವಿಧಾನ';

  @override
  String get storeModeUpiHint => 'ರೈತರು QR ಸ್ಕ್ಯಾನ್ ಮಾಡುತ್ತಾರೆ';

  @override
  String get storeModeCardHint => 'ಸ್ಟೋರ್ ಟರ್ಮಿನಲ್‌ನಲ್ಲಿ ಕಾರ್ಡ್';

  @override
  String get storeModeCashHint => 'ನಗದು ಎಣಿಸಿ, ಚಿಲ್ಲರೆ ಕೊಡಿ';

  @override
  String get storeModeCreditHint => 'ರೈತರ ಖಾತೆಗೆ ಸೇರಿಸಿ';

  @override
  String get storeCardReference => 'ಟರ್ಮಿನಲ್ ಉಲ್ಲೇಖ';

  @override
  String get storeCardReferenceHint => 'ಸ್ಲಿಪ್‌ನಲ್ಲಿರುವ ಅನುಮೋದನೆ ಕೋಡ್';

  @override
  String get storeCardReferenceRequired => 'ಟರ್ಮಿನಲ್ ಉಲ್ಲೇಖ ನಮೂದಿಸಿ';

  @override
  String get storeCashTendered => 'ಪಡೆದ ನಗದು';

  @override
  String get storeCashChange => 'ಕೊಡಬೇಕಾದ ಚಿಲ್ಲರೆ';

  @override
  String get storeCashShort => 'ಪಡೆದ ನಗದು ಒಟ್ಟು ಮೊತ್ತಕ್ಕಿಂತ ಕಡಿಮೆ';

  @override
  String get storeCreditNeedsFarmer =>
      'ಸಾಲಕ್ಕೆ ನೋಂದಾಯಿತ ರೈತರು ಬೇಕು. ಫೋನ್ ಮೂಲಕ ರೈತರನ್ನು ಹುಡುಕಿ.';

  @override
  String get storeInvoicePreview => 'GST ಇನ್‌ವಾಯ್ಸ್ ಮುನ್ನೋಟ';

  @override
  String get storeInvoicePreviewNote =>
      'ನೀವು ದೃಢೀಕರಿಸಿದಾಗ ಇನ್‌ವಾಯ್ಸ್ ಸಂಖ್ಯೆ ಮತ್ತು ಅಂತಿಮ ತೆರಿಗೆ ಸರ್ವರ್‌ನಿಂದ ಬರುತ್ತದೆ.';

  @override
  String get storeColItem => 'ವಸ್ತು';

  @override
  String get storeColHsn => 'HSN';

  @override
  String get storeColQty => 'ಪ್ರಮಾಣ';

  @override
  String get storeColRate => 'ದರ';

  @override
  String get storeColGst => 'GST';

  @override
  String get storeColAmount => 'ಮೊತ್ತ';

  @override
  String get storeTaxable => 'ತೆರಿಗೆ ವಿಧಿಸಬಹುದಾದ ಮೌಲ್ಯ';

  @override
  String get storeCgst => 'CGST';

  @override
  String get storeSgst => 'SGST';

  @override
  String get storeIgst => 'IGST';

  @override
  String get storeConfirmSale => 'ಮಾರಾಟ ದೃಢೀಕರಿಸಿ';

  @override
  String get storeOfflineSaleTitle => 'ಆಫ್‌ಲೈನ್: ಮಾರಾಟ ಪೂರ್ಣಗೊಳ್ಳುವುದಿಲ್ಲ';

  @override
  String get storeOfflineSaleHelp =>
      'ಕಾರ್ಟ್ ಹಾಗೆಯೇ ಇದೆ. ನೆಟ್‌ವರ್ಕ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ ಮತ್ತೆ ದೃಢೀಕರಿಸಿ.';

  @override
  String get storeApprovalNeededTitle => 'ಸಾಲ ಅನುಮೋದನೆ ಬೇಕು';

  @override
  String storeApprovalNeededHelp(String amount) {
    return 'ಈ ಮಾರಾಟ ರೈತರ ಮಿತಿಗಿಂತ $amount ಹೆಚ್ಚು. ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರು ಅನುಮೋದಿಸಬೇಕು. ಕಾರ್ಟ್ ಹಾಗೆಯೇ ಇದೆ.';
  }

  @override
  String get storeCreditBalance => 'ಖಾತೆ ಬಾಕಿ';

  @override
  String get storeCreditLimit => 'ಸಾಲ ಮಿತಿ';

  @override
  String get storeChooseAnotherMode => 'ಇನ್ನೊಂದು ವಿಧಾನ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get storeSaleFailedTitle => 'ಮಾರಾಟ ಪೂರ್ಣಗೊಂಡಿಲ್ಲ';

  @override
  String storeSaleFailed(String code) {
    return 'ಸರ್ವರ್ ಮಾರಾಟವನ್ನು ನಿರಾಕರಿಸಿದೆ ($code). ಕಾರ್ಟ್ ಹಾಗೆಯೇ ಇದೆ.';
  }

  @override
  String get storeInvoiceTitle => 'ತೆರಿಗೆ ಇನ್‌ವಾಯ್ಸ್';

  @override
  String storeInvoiceNo(String number) {
    return 'ಇನ್‌ವಾಯ್ಸ್ $number';
  }

  @override
  String get storeInvoicePaid => 'ಮಾರಾಟ ಪೂರ್ಣಗೊಂಡಿದೆ';

  @override
  String get storeInvoiceBuyer => 'ಬಿಲ್ ಪಡೆದವರು';

  @override
  String storeGstin(String gstin) {
    return 'GSTIN $gstin';
  }

  @override
  String get storeAmountInWords => 'ಅಕ್ಷರಗಳಲ್ಲಿ ಮೊತ್ತ';

  @override
  String get storeOpenPdf => 'PDF ತೆರೆಯಿರಿ';

  @override
  String get storeShareWhatsApp => 'WhatsAppನಲ್ಲಿ ಕಳುಹಿಸಿ';

  @override
  String get storeShareOther => 'ಹಂಚಿಕೊಳ್ಳಿ';

  @override
  String storeShareSent(String to) {
    return '$to ಗೆ ಕಳುಹಿಸಲಾಗಿದೆ';
  }

  @override
  String get storeShareFailed => 'ಕಳುಹಿಸಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get storePdfFailed => 'PDF ತೆರೆಯಲಾಗಲಿಲ್ಲ.';

  @override
  String storeShareText(String number, String amount, String url) {
    return 'ಇನ್‌ವಾಯ್ಸ್ $number, ಮೊತ್ತ $amount: $url';
  }

  @override
  String get storeNextSale => 'ಮುಂದಿನ ಮಾರಾಟ';

  @override
  String get storeQueueTitle => 'ಆರ್ಡರ್ ಸರದಿ';

  @override
  String storeOrderRef(String ref) {
    return 'ಆರ್ಡರ್ #$ref';
  }

  @override
  String get storeChannelOfficer => 'ಕ್ಷೇತ್ರ ಅಧಿಕಾರಿ';

  @override
  String get storeChannelFarmerApp => 'ರೈತ ಆ್ಯಪ್';

  @override
  String get storeChannelPos => 'ಕೌಂಟರ್';

  @override
  String get storeFulfilmentPickup => 'ಅಂಗಡಿಯಲ್ಲಿ ಪಡೆಯುವುದು';

  @override
  String get storeFulfilmentDelivery => 'ಡೆಲಿವರಿ';

  @override
  String get storeStatusPlaced => 'ಆರ್ಡರ್ ಆಗಿದೆ';

  @override
  String get storeStatusReserved => 'ಸ್ಟಾಕ್ ಕಾಯ್ದಿರಿಸಲಾಗಿದೆ';

  @override
  String get storeStatusPacked => 'ಪ್ಯಾಕ್ ಆಗಿದೆ';

  @override
  String get storeStatusReady => 'ಸಿದ್ಧ';

  @override
  String get storeStatusHandedOver => 'ಹಸ್ತಾಂತರಿಸಲಾಗಿದೆ';

  @override
  String get storeStatusDelivered => 'ತಲುಪಿಸಲಾಗಿದೆ';

  @override
  String get storeStatusCancelled => 'ರದ್ದಾಗಿದೆ';

  @override
  String get storeActionReserve => 'ಸ್ಟಾಕ್ ಕಾಯ್ದಿರಿಸಿ';

  @override
  String get storeActionPack => 'ಪ್ಯಾಕ್ ಆಗಿದೆ ಎಂದು ಗುರುತಿಸಿ';

  @override
  String get storeActionReady => 'ಸಿದ್ಧ ಎಂದು ಗುರುತಿಸಿ';

  @override
  String get storeActionHandOver => 'ಹಸ್ತಾಂತರಿಸಿ';

  @override
  String get storeActionDeliver => 'ತಲುಪಿಸಲಾಗಿದೆ ಎಂದು ಗುರುತಿಸಿ';

  @override
  String get storeActionCancel => 'ಆರ್ಡರ್ ರದ್ದುಮಾಡಿ';

  @override
  String get storeCancelReason => 'ರದ್ದತಿಯ ಕಾರಣ';

  @override
  String get storeKeepOrder => 'ಆರ್ಡರ್ ಉಳಿಸಿ';

  @override
  String get storeTransitionFailed =>
      'ಈ ಬದಲಾವಣೆಗೆ ಈಗ ಅನುಮತಿ ಇಲ್ಲ. ಪಟ್ಟಿ ನವೀಕರಿಸಲಾಗಿದೆ.';

  @override
  String get storeQueueEmpty => 'ಇಲ್ಲಿ ಆರ್ಡರ್‌ಗಳಿಲ್ಲ';

  @override
  String get storeQueueEmptyHelp =>
      'ಕ್ಷೇತ್ರ ಅಧಿಕಾರಿಗಳು ಮತ್ತು ರೈತ ಆ್ಯಪ್‌ನ ಆರ್ಡರ್‌ಗಳು ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.';

  @override
  String get storeSelectOrder => 'ವಿವರಗಳಿಗಾಗಿ ಒಂದು ಆರ್ಡರ್ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String storeFarmerUnknown(String ref) {
    return 'ರೈತ $ref';
  }

  @override
  String storeOrderMoved(String status) {
    return 'ಆರ್ಡರ್ ಈಗ: $status';
  }

  @override
  String get storeStockTitle => 'ಸ್ಟಾಕ್';

  @override
  String get storeOnHand => 'ಕೈಯಲ್ಲಿ';

  @override
  String get storeReserved => 'ಕಾಯ್ದಿರಿಸಿದವು';

  @override
  String get storeAvailable => 'ಲಭ್ಯ';

  @override
  String storeBatch(String number) {
    return 'ಬ್ಯಾಚ್ $number';
  }

  @override
  String storeExpires(String date) {
    return 'ಅವಧಿ ಮುಕ್ತಾಯ $date';
  }

  @override
  String get storeNoExpiry => 'ಅವಧಿ ಇಲ್ಲ';

  @override
  String get storeExpired => 'ಅವಧಿ ಮುಗಿದಿದೆ';

  @override
  String get storeExpiring30 => '30 ದಿನಗಳಲ್ಲಿ ಅವಧಿ ಮುಕ್ತಾಯ';

  @override
  String get storeExpiring60 => '60 ದಿನಗಳಲ್ಲಿ ಅವಧಿ ಮುಕ್ತಾಯ';

  @override
  String get storeFilterLow => 'ಕಡಿಮೆ ಸ್ಟಾಕ್';

  @override
  String get storeFilterExpiring => 'ಅವಧಿ ಸಮೀಪ';

  @override
  String get storeStockEmpty => 'ಹೊಂದುವ ಸ್ಟಾಕ್ ಇಲ್ಲ';

  @override
  String get storeStockEmptyHelp => 'ಫಿಲ್ಟರ್ ಬದಲಿಸಿ ಅಥವಾ ಸರಕು ಸ್ವೀಕರಿಸಿ.';

  @override
  String get storeSelectSku => 'ಬ್ಯಾಚ್‌ಗಳನ್ನು ನೋಡಲು ವಸ್ತು ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get storeWriteOff => 'ಬರೆದು ತೆಗೆಯಿರಿ';

  @override
  String get storeWriteOffTitle => 'ಸ್ಟಾಕ್ ಬರೆದು ತೆಗೆಯಿರಿ';

  @override
  String get storeAdjust => 'ಎಣಿಕೆ ಸರಿಪಡಿಸಿ';

  @override
  String get storeAdjustTitle => 'ಎಣಿಸಿದ ಸ್ಟಾಕ್‌ಗೆ ಸರಿಪಡಿಸಿ';

  @override
  String get storeCountedQty => 'ಎಣಿಸಿದ ಪ್ರಮಾಣ';

  @override
  String get storeAdjustReasonHint => 'ಎಣಿಕೆ ಏಕೆ ಬೇರೆಯಾಗಿದೆ';

  @override
  String get storeReason => 'ಕಾರಣ';

  @override
  String get storeReasonRequired => 'ಕಾರಣ ನಮೂದಿಸಿ';

  @override
  String get storeReasonDamage => 'ಹಾಳಾಗಿದೆ';

  @override
  String get storeReasonExpiry => 'ಅವಧಿ ಮುಗಿದಿದೆ';

  @override
  String get storeReasonOther => 'ಇತರೆ';

  @override
  String get storeQuantity => 'ಪ್ರಮಾಣ';

  @override
  String get storeQtyRequired => 'ಸೊನ್ನೆಗಿಂತ ಹೆಚ್ಚಿನ ಪ್ರಮಾಣ ನಮೂದಿಸಿ';

  @override
  String storeQtyTooHigh(String qty) {
    return 'ಲಭ್ಯಕ್ಕಿಂತ ಹೆಚ್ಚು ($qty)';
  }

  @override
  String storeAvailableQty(String qty) {
    return 'ಲಭ್ಯ: $qty';
  }

  @override
  String get storeAddPhoto => 'ಫೋಟೋ ಸೇರಿಸಿ';

  @override
  String get storePhotoAdded => 'ಫೋಟೋ ಸೇರಿಸಲಾಗಿದೆ';

  @override
  String get storeNote => 'ಟಿಪ್ಪಣಿ';

  @override
  String get storeSubmit => 'ಉಳಿಸಿ';

  @override
  String get storeSaved => 'ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get storeNegativeStock => 'ಕಾಯ್ದಿರಿಸದ ಸ್ಟಾಕ್ ಸಾಕಾಗುವುದಿಲ್ಲ';

  @override
  String get storeReceiptTitle => 'ಸರಕು ಸ್ವೀಕಾರ';

  @override
  String get storeReference => 'ಪೂರೈಕೆದಾರರ ಇನ್‌ವಾಯ್ಸ್ / ಉಲ್ಲೇಖ';

  @override
  String get storeSku => 'ವಸ್ತು';

  @override
  String get storeFindSku => 'ವಸ್ತು (ಆಯ್ಕೆ ಅಥವಾ ಸ್ಕ್ಯಾನ್)';

  @override
  String get storeSkuRequired => 'ವಸ್ತು ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get storeBatchNo => 'ಬ್ಯಾಚ್ ಸಂಖ್ಯೆ';

  @override
  String get storeBatchNoRequired => 'ಬ್ಯಾಚ್ ಸಂಖ್ಯೆ ನಮೂದಿಸಿ';

  @override
  String get storeExpiryDate => 'ಅವಧಿ ಮುಕ್ತಾಯ ದಿನಾಂಕ';

  @override
  String get storeExpiryPast => 'ಅವಧಿ ದಿನಾಂಕ ಕಳೆದಿದೆ';

  @override
  String get storeUnitCost => 'ಘಟಕ ಬೆಲೆ (₹)';

  @override
  String get storeCostRequired => 'ಬೆಲೆ ನಮೂದಿಸಿ';

  @override
  String get storeAddLine => 'ಸಾಲು ಸೇರಿಸಿ';

  @override
  String get storeRemoveLine => 'ಸಾಲು ತೆಗೆದುಹಾಕಿ';

  @override
  String get storeReceiptSubmit => 'ಸ್ಟಾಕ್ ಸ್ವೀಕರಿಸಿ';

  @override
  String get storeReceiptDone => 'ಸ್ಟಾಕ್ ಸ್ವೀಕರಿಸಲಾಗಿದೆ';

  @override
  String storeReceiptDoneHelp(int lines, String qty) {
    return 'ಸಾಲುಗಳು: $lines · ಸೇರಿಸಿದ ಘಟಕಗಳು: $qty';
  }

  @override
  String get storeBatchMismatch =>
      'ಈ ಬ್ಯಾಚ್ ಬೇರೆ ಅವಧಿ ದಿನಾಂಕದೊಂದಿಗೆ ಈಗಾಗಲೇ ಇದೆ';

  @override
  String get storeTransferTitle => 'ಸ್ಟಾಕ್ ವರ್ಗಾವಣೆ';

  @override
  String get storeToStore => 'ಯಾವ ಸ್ಟೋರ್‌ಗೆ';

  @override
  String get storeToStoreRequired => 'ಗಮ್ಯ ಸ್ಟೋರ್ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get storeNoOtherStores =>
      'ನಿಮಗೆ ಬೇರೆ ಸ್ಟೋರ್ ಲಭ್ಯವಿಲ್ಲ. ನಿಮ್ಮ ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರನ್ನು ಕೇಳಿ.';

  @override
  String get storeChooseBatch => 'ಬ್ಯಾಚ್';

  @override
  String get storeFefoSuggested => 'ಮೊದಲು ಅವಧಿ ಮುಗಿಯುವುದು ಮೊದಲು (ಸಲಹೆ)';

  @override
  String get storeTransferSubmit => 'ವರ್ಗಾಯಿಸಿ';

  @override
  String get storeTransferDone => 'ವರ್ಗಾವಣೆ ಪೂರ್ಣಗೊಂಡಿದೆ';

  @override
  String get storeCreditTitle => 'ಸಾಲ';

  @override
  String get storeApprovalsEmpty => 'ಬಾಕಿ ಅನುಮೋದನೆಗಳಿಲ್ಲ';

  @override
  String get storeApprovalAmount => 'ಮಾರಾಟ ಮೊತ್ತ';

  @override
  String get storeShortfall => 'ಮಿತಿಗಿಂತ ಹೆಚ್ಚು';

  @override
  String get storeApprove => 'ಅನುಮೋದಿಸಿ';

  @override
  String get storeReject => 'ತಿರಸ್ಕರಿಸಿ';

  @override
  String get storeDecisionNote => 'ಟಿಪ್ಪಣಿ (ಐಚ್ಛಿಕ)';

  @override
  String get storeApproved =>
      'ಅನುಮೋದಿಸಲಾಗಿದೆ. ಸ್ಟೋರ್ ಮಾರಾಟವನ್ನು ಒಮ್ಮೆ ಪೂರ್ಣಗೊಳಿಸಬಹುದು.';

  @override
  String get storeRejected => 'ತಿರಸ್ಕರಿಸಲಾಗಿದೆ';

  @override
  String get storeApprovalGone => 'ಈ ವಿನಂತಿಯ ಬಗ್ಗೆ ಈಗಾಗಲೇ ನಿರ್ಧರಿಸಲಾಗಿದೆ';

  @override
  String get storeSetLimitTitle => 'ರೈತರ ಸಾಲ ಮಿತಿ ನಿಗದಿಪಡಿಸಿ';

  @override
  String get storeLimitAmount => 'ಮಿತಿ (₹)';

  @override
  String get storeLimitAmountRequired => 'ಮಿತಿಯನ್ನು ರೂಪಾಯಿಗಳಲ್ಲಿ ನಮೂದಿಸಿ';

  @override
  String get storeSetLimit => 'ಮಿತಿ ಉಳಿಸಿ';

  @override
  String storeLimitSaved(String amount) {
    return 'ಮಿತಿ ಉಳಿಸಲಾಗಿದೆ: $amount';
  }

  @override
  String storeLimitNeedsClusterHead(String cap) {
    return '$cap ಮೀರಿದ ಮಿತಿಗೆ ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರು ಬೇಕು. ಈ ಮಿತಿ ನಿಗದಿಪಡಿಸಲು ನಿಮ್ಮ ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರನ್ನು ಕೇಳಿ.';
  }

  @override
  String get storeLimitFarmerNotFound =>
      'ಈ ಫೋನ್ ಸಂಖ್ಯೆಯ ರೈತರು ಈ ಟ್ಯಾಬ್ಲೆಟ್‌ನಲ್ಲಿ ಇಲ್ಲ';

  @override
  String storeManagerCapHint(String cap) {
    return 'ನೀವು $cap ವರೆಗೆ ನಿಗದಿಪಡಿಸಬಹುದು';
  }

  @override
  String get storeDayCloseTitle => 'ದಿನದ ಮುಕ್ತಾಯ';

  @override
  String get storeCashCount => 'ನಗದು ಎಣಿಕೆ';

  @override
  String get storeCoins => 'ನಾಣ್ಯಗಳು (₹)';

  @override
  String get storeExpectedCash => 'ಇರಬೇಕಾದ ನಗದು';

  @override
  String get storeCountedCash => 'ಎಣಿಸಿದ ನಗದು';

  @override
  String get storeVariance => 'ವ್ಯತ್ಯಾಸ';

  @override
  String storeVarianceOver(String threshold) {
    return 'ವ್ಯತ್ಯಾಸ $threshold ಮೀರಿದೆ: ಲೆಕ್ಕಪರಿಶೋಧಕರಿಗೆ ತಿಳಿಸಲಾಗುತ್ತದೆ';
  }

  @override
  String get storeDepositSlip => 'ಬ್ಯಾಂಕ್ ಠೇವಣಿ ಸ್ಲಿಪ್ ಫೋಟೋ';

  @override
  String get storeTakePhoto => 'ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get storeRetakePhoto => 'ಮತ್ತೆ ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get storeSlipRequired => 'ಠೇವಣಿ ಸ್ಲಿಪ್‌ನ ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get storeCloseNotes => 'ಟಿಪ್ಪಣಿಗಳು';

  @override
  String get storeCloseDay => 'ದಿನ ಮುಗಿಸಿ';

  @override
  String get storeDayClosedTitle => 'ದಿನ ಮುಗಿದಿದೆ';

  @override
  String get storeDayAlreadyClosed =>
      'ಇಂದು ಈಗಾಗಲೇ ಮುಚ್ಚಲಾಗಿದೆ. ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರು ಮತ್ತೆ ತೆರೆಯಬಹುದು.';

  @override
  String get storeFlagged => 'ಲೆಕ್ಕಪರಿಶೋಧನೆಗೆ ಗುರುತಿಸಲಾಗಿದೆ';

  @override
  String get storePreviewEstimate => 'ಅಂದಾಜು';

  @override
  String get storePreviewLoading => 'ಮುನ್ನೋಟ ನವೀಕರಿಸಲಾಗುತ್ತಿದೆ…';

  @override
  String get storePreviewServerNote =>
      'ಇನ್‌ವಾಯ್ಸ್‌ನಂತೆಯೇ ಸರ್ವರ್ ಬೆಲೆ ನಿಗದಿಪಡಿಸಿದೆ. ನೀವು ದೃಢೀಕರಿಸಿದಾಗ ಇನ್‌ವಾಯ್ಸ್ ಸಂಖ್ಯೆ ಬರುತ್ತದೆ.';

  @override
  String get storePreviewOffline =>
      'ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿ ಮುನ್ನೋಟ ಲಭ್ಯವಿಲ್ಲ. ಮೊತ್ತಗಳು ಅಂದಾಜು ಮಾತ್ರ; ನೀವು ದೃಢೀಕರಿಸಿದಾಗ ಸರ್ವರ್ ಇನ್‌ವಾಯ್ಸ್ ಬೆಲೆ ನಿಗದಿಪಡಿಸುತ್ತದೆ.';

  @override
  String get storePreviewUnavailable =>
      'ಮುನ್ನೋಟ ಲಭ್ಯವಿಲ್ಲ. ಮೊತ್ತಗಳು ಅಂದಾಜು ಮಾತ್ರ; ನೀವು ದೃಢೀಕರಿಸಿದಾಗ ಸರ್ವರ್ ಇನ್‌ವಾಯ್ಸ್ ಬೆಲೆ ನಿಗದಿಪಡಿಸುತ್ತದೆ.';

  @override
  String get storeCheckApproval => 'ಅನುಮೋದನೆ ಪರಿಶೀಲಿಸಿ';

  @override
  String get storeApprovalPending =>
      'ಇನ್ನೂ ಅನುಮೋದನೆ ಸಿಕ್ಕಿಲ್ಲ. ಕಾರ್ಟ್ ಹಾಗೆಯೇ ಇದೆ; ನಂತರ ಮತ್ತೆ ಪರಿಶೀಲಿಸಿ.';

  @override
  String get storeApprovalRejected =>
      'ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರು ಈ ಸಾಲದ ಮಾರಾಟವನ್ನು ತಿರಸ್ಕರಿಸಿದ್ದಾರೆ. ಬೇರೆ ವಿಧಾನ ಆಯ್ಕೆಮಾಡಿ.';

  @override
  String get storeApprovalCheckOffline =>
      'ಅನುಮೋದನೆ ಪರಿಶೀಲಿಸಲಾಗಲಿಲ್ಲ. ಇಂಟರ್ನೆಟ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get storeTransferSourceNotAllowed =>
      'ನೀವು ನಿಮ್ಮ ಸ್ವಂತ ಸ್ಟೋರ್‌ನಿಂದ ಮಾತ್ರ ಸ್ಟಾಕ್ ಕಳುಹಿಸಬಹುದು.';

  @override
  String get storeTransferDestinationNotAllowed =>
      'ಆ ಸ್ಟೋರ್‌ಗೆ ನೀವು ಸ್ಟಾಕ್ ಕಳುಹಿಸಲಾಗದು. ಪಟ್ಟಿಯಿಂದ ಸ್ಟೋರ್ ಆಯ್ಕೆಮಾಡಿ.';

  @override
  String storeDistanceKm(String km) {
    return '$km ಕಿ.ಮೀ. ದೂರ';
  }

  @override
  String get creditApprovedSending =>
      'ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರು ಅನುಮೋದಿಸಿದ್ದಾರೆ. ಮಾರಾಟ ಕಳುಹಿಸಲಾಗುತ್ತಿದೆ…';

  @override
  String get creditRejectedByClusterHead =>
      'ಕ್ಲಸ್ಟರ್ ಮುಖ್ಯಸ್ಥರು ಈ ಸಾಲದ ಮಾರಾಟವನ್ನು ತಿರಸ್ಕರಿಸಿದ್ದಾರೆ. ಬದಲಿಗೆ ನಗದು ಪಡೆಯಿರಿ.';

  @override
  String get loginDeviceNotBound =>
      'ಈ ಫೋನ್ ನಿಮ್ಮ ಹೆಸರಿನಲ್ಲಿ ನೋಂದಣಿ ಆಗಿಲ್ಲ. ಇದನ್ನು ಅನುಮೋದಿಸಲು ನಿಮ್ಮ ಆಡಳಿತಗಾರರನ್ನು ಕೇಳಿ, ನಂತರ ಮತ್ತೆ ಸೈನ್ ಇನ್ ಮಾಡಿ.';

  @override
  String get wipeTitle => 'ನಿಮ್ಮ ಆಡಳಿತಗಾರರು ಸೈನ್ ಔಟ್ ಮಾಡಿದ್ದಾರೆ';

  @override
  String get wipeBody =>
      'ನಿಮ್ಮ ಆಡಳಿತಗಾರರು ಈ ಫೋನ್ ಅನ್ನು ಆ್ಯಪ್‌ನಿಂದ ಸೈನ್ ಔಟ್ ಮಾಡಿದ್ದಾರೆ. ಸುರಕ್ಷತೆಗಾಗಿ ಈ ಫೋನ್‌ನಲ್ಲಿನ ಆ್ಯಪ್ ಡೇಟಾ ಅಳಿಸಲಾಗಿದೆ.';

  @override
  String get wipeDeletedList =>
      'ಅಳಿಸಲಾಗಿದೆ: ಉಳಿಸಿದ ರೈತರು, ಭೇಟಿಗಳು, ಆರ್ಡರ್‌ಗಳು, ಫೋಟೋಗಳು ಮತ್ತು ಇನ್ನೂ ಕಳುಹಿಸದ ಕೆಲಸ. ನಿಮ್ಮ ಭಾಷೆ ಸೆಟ್ಟಿಂಗ್ ಹಾಗೆಯೇ ಇರುತ್ತದೆ.';

  @override
  String get wipeWhatNext =>
      'ಇದು ತಪ್ಪಾಗಿದ್ದರೆ ನಿಮ್ಮ ಆಡಳಿತಗಾರರನ್ನು ಸಂಪರ್ಕಿಸಿ. ಅವರು ಅನುಮತಿಸಿದ ನಂತರ ನೀವು ಮತ್ತೆ ಸೈನ್ ಇನ್ ಮಾಡಬಹುದು.';

  @override
  String get wipeSignInAgain => 'ಮತ್ತೆ ಸೈನ್ ಇನ್ ಮಾಡಿ';

  @override
  String get audioListen => 'ಕೇಳಿ';

  @override
  String get audioUnavailable => 'ಧ್ವನಿ ಲಭ್ಯವಿಲ್ಲ';

  @override
  String get kisanLanguagePrompt =>
      'ನೀವು ಕನ್ನಡ ಆಯ್ಕೆ ಮಾಡಿದ್ದೀರಿ. ಮುಂದುವರಿಸಿ ಒತ್ತಿ.';

  @override
  String get kisanAbout => 'ಆ್ಯಪ್ ಬಗ್ಗೆ';

  @override
  String kisanAboutVersion(String app, String version) {
    return '$app ಆವೃತ್ತಿ $version';
  }

  @override
  String kisanAcres(String count) {
    return '$count ಎಕರೆ';
  }

  @override
  String kisanAcresPlus(String count) {
    return '$count+ ಎಕರೆ';
  }

  @override
  String get kisanAddToCart => 'ಬುಟ್ಟಿಗೆ ಸೇರಿಸಿ';

  @override
  String kisanAsOf(String time) {
    return '$timeಕ್ಕೆ ನವೀಕರಿಸಲಾಗಿದೆ';
  }

  @override
  String kisanOfflineAsOf(String time) {
    return 'ಇಂಟರ್ನೆಟ್ ಇಲ್ಲ. $timeಕ್ಕೆ ಉಳಿಸಿದ್ದು';
  }

  @override
  String kisanBalanceNow(String amount) {
    return 'ಈಗಿನ ಬಾಕಿ: $amount';
  }

  @override
  String get kisanBuyProducts => 'ಸಾಮಗ್ರಿ ಖರೀದಿಸಿ';

  @override
  String get kisanCall => 'ಕರೆ ಮಾಡಿ';

  @override
  String get kisanCartEmpty => 'ನಿಮ್ಮ ಬುಟ್ಟಿ ಖಾಲಿ ಇದೆ';

  @override
  String get kisanCartTitle => 'ನನ್ನ ಬುಟ್ಟಿ';

  @override
  String get kisanCheckMyCrop => 'ನನ್ನ ಬೆಳೆ ಪರೀಕ್ಷಿಸಿ';

  @override
  String get kisanConfirmWithoutRating => 'ರೇಟಿಂಗ್ ಇಲ್ಲದೆ ದೃಢೀಕರಿಸಿ';

  @override
  String get kisanConsentAgree => 'ನಾನು ಒಪ್ಪುತ್ತೇನೆ';

  @override
  String get kisanConsentDataHowToStop =>
      'ಕಿಸಾನ್ ಬಳಸಲು ಇದು ಬೇಕು. ನಿಲ್ಲಿಸಲು ನಿಮ್ಮ ಖಾತೆ ಅಳಿಸಿ.';

  @override
  String get kisanConsentDataNeeded =>
      'ಕಿಸಾನ್ ಬಳಸಲು ಮೊದಲ ಕಾರ್ಡ್‌ಗೆ ಹೌದು ಎನ್ನಿ.';

  @override
  String get kisanConsentDataNotice =>
      'ಸಲಹೆ ನೀಡಲು ನಿಮ್ಮ ಹೆಸರು, ಫೋನ್, ಊರು, ಹೊಲ ಮತ್ತು ಬೆಳೆ ಫೋಟೋಗಳನ್ನು ಇಡುತ್ತೇವೆ. ನಿಮ್ಮ ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ ಮತ್ತು ಅಂಗಡಿ ಅವನ್ನು ನೋಡಬಹುದು. ನಿಮ್ಮ ಮಾಹಿತಿಯನ್ನು ನಾವು ಎಂದಿಗೂ ಮಾರುವುದಿಲ್ಲ.';

  @override
  String kisanConsentGivenOn(String date) {
    return '$dateರಂದು ನೀಡಲಾಗಿದೆ';
  }

  @override
  String get kisanConsentIntro =>
      'ದಯವಿಟ್ಟು ಓದಿ ಅಥವಾ ಕೇಳಿ. ಎರಡನೇ ಆಯ್ಕೆಯನ್ನು ಯಾವಾಗ ಬೇಕಾದರೂ “ನಾನು”ನಲ್ಲಿ ಬದಲಿಸಬಹುದು.';

  @override
  String get kisanConsentOffersNotice =>
      'ಆಫರ್‌ಗಳು ಮತ್ತು ಕೃಷಿ ಸಲಹೆಗಳನ್ನು SMS ಅಥವಾ WhatsAppನಲ್ಲಿ ಕಳುಹಿಸುತ್ತೇವೆ. “ನಾನು”ನಲ್ಲಿ ಯಾವಾಗ ಬೇಕಾದರೂ ನಿಲ್ಲಿಸಬಹುದು.';

  @override
  String get kisanConsentPending =>
      'ಈ ಫೋನ್‌ನಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ. ಇಂಟರ್ನೆಟ್ ಬಂದಾಗ ಕಳುಹಿಸುತ್ತೇವೆ.';

  @override
  String get kisanConsentSettings => 'ನನ್ನ ಒಪ್ಪಿಗೆ';

  @override
  String get kisanConsentTitle => 'ಆರಂಭಿಸುವ ಮೊದಲು';

  @override
  String kisanConsentWithdrawnOn(String date) {
    return '$dateರಂದು ನಿಲ್ಲಿಸಲಾಗಿದೆ';
  }

  @override
  String get kisanCouldNotOpen => 'ತೆರೆಯಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get kisanCreditStoreWillConfirm => 'ನಿಮ್ಮ ಅಂಗಡಿ ದೃಢಪಡಿಸುತ್ತದೆ';

  @override
  String get kisanCropDoctorSoonHelp =>
      'ಶೀಘ್ರದಲ್ಲೇ ಇಲ್ಲಿ ಬೆಳೆಯ ಫೋಟೋ ತೆಗೆದು ಸಲಹೆ ಪಡೆಯಬಹುದು.';

  @override
  String get kisanCropDoctorSoonTitle => 'ಬೆಳೆ ವೈದ್ಯ ಶೀಘ್ರದಲ್ಲೇ ಬರುತ್ತಿದೆ';

  @override
  String get kisanCropUnknown => 'ಬೆಳೆ';

  @override
  String get kisanDeleteAccount => 'ನನ್ನ ಖಾತೆ ಅಳಿಸಿ';

  @override
  String get kisanDeleteAfter =>
      'ಅಲ್ಲಿಯವರೆಗೆ ಕಿಸಾನ್ ಬಳಸಬಹುದು. ಮನಸ್ಸು ಬದಲಾದರೆ ನಿಮ್ಮ ಅಂಗಡಿಗೆ ಕರೆ ಮಾಡಿ.';

  @override
  String get kisanDeleteAreYouSure =>
      'ಖಚಿತವೇ? ನಿಮ್ಮ ಖಾತೆ ಮತ್ತು ಮಾಹಿತಿ ಅಳಿಸಲಾಗುತ್ತದೆ. ಇದನ್ನು ಹಿಂಪಡೆಯಲು ಆಗುವುದಿಲ್ಲ.';

  @override
  String kisanDeleteDueBy(String date) {
    return '$dateರೊಳಗೆ ಮುಗಿಸುತ್ತೇವೆ';
  }

  @override
  String get kisanDeleteExplain =>
      'ನಿಮ್ಮ ಖಾತೆ, ಹೊಲದ ವಿವರ, ಬೆಳೆ ಫೋಟೋಗಳು ಮತ್ತು ಸಂದೇಶಗಳನ್ನು ಅಳಿಸುತ್ತೇವೆ. ಬಿಲ್‌ಗಳಂತಹ ಕಾನೂನು ಕೇಳುವ ದಾಖಲೆಗಳನ್ನು ಸ್ವಲ್ಪ ಕಾಲ ಇಟ್ಟು ನಂತರ ಅಳಿಸುತ್ತೇವೆ.';

  @override
  String get kisanDeleteKeep => 'ಬೇಡ, ನನ್ನ ಖಾತೆ ಇರಲಿ';

  @override
  String get kisanDeleteKeepsDues =>
      'ಖಾತೆ ಅಳಿಸಿದ ನಂತರವೂ ಅಂಗಡಿಗೆ ಕೊಡಬೇಕಾದ ಬಾಕಿ ಕಟ್ಟಬೇಕು.';

  @override
  String kisanDeleteRequested(String ticket) {
    return 'ವಿನಂತಿ ಕಳುಹಿಸಲಾಗಿದೆ · $ticket';
  }

  @override
  String get kisanDeleteStatusCompleted => 'ನಿಮ್ಮ ಖಾತೆ ಅಳಿಸಲಾಗಿದೆ';

  @override
  String get kisanDeleteStatusInProgress => 'ನಿಮ್ಮ ಮಾಹಿತಿಯನ್ನು ಅಳಿಸುತ್ತಿದ್ದೇವೆ';

  @override
  String get kisanDeleteStatusReceived => 'ನಿಮ್ಮ ವಿನಂತಿ ಸಿಕ್ಕಿದೆ';

  @override
  String kisanDeleteTicket(String ticket) {
    return 'ಟಿಕೆಟ್ $ticket';
  }

  @override
  String get kisanDeleteYes => 'ಹೌದು, ಅಳಿಸಿ';

  @override
  String get kisanDelivery => 'ಮನೆಗೆ ತಲುಪಿಸಿ';

  @override
  String kisanDuesTitle(String amount) {
    return 'ನಿಮ್ಮ ಬಾಕಿ $amount';
  }

  @override
  String get kisanFarmUnnamed => 'ನನ್ನ ಹೊಲ';

  @override
  String get kisanFieldOfficer => 'ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ';

  @override
  String get kisanGoToPay => 'ಪಾವತಿಗೆ ಹೋಗಿ';

  @override
  String kisanGreeting(String name) {
    return 'ನಮಸ್ತೆ, $name';
  }

  @override
  String get kisanGreetingNoName => 'ನಮಸ್ತೆ';

  @override
  String get kisanHelpCallStore => 'ಸಹಾಯ: ಅಂಗಡಿಗೆ ಕರೆ ಮಾಡಿ';

  @override
  String get kisanHelpNoPhone => 'ಅಂಗಡಿಯ ಫೋನ್ ಇನ್ನೂ ಇಲ್ಲ';

  @override
  String get kisanHowMany => 'ಎಷ್ಟು ಬೇಕು?';

  @override
  String get kisanHowPay => 'ಹೇಗೆ ಪಾವತಿಸುತ್ತೀರಿ?';

  @override
  String kisanInStock(String count) {
    return 'ನಿಮ್ಮ ಅಂಗಡಿಯಲ್ಲಿ $count ಇವೆ';
  }

  @override
  String get kisanIrrigationQuestion => 'ಹೊಲಕ್ಕೆ ನೀರು ಹೇಗೆ ಕೊಡುತ್ತೀರಿ?';

  @override
  String get kisanIrrigationUnknown => 'ನೀರು: ಗೊತ್ತಿಲ್ಲ';

  @override
  String get kisanItems => 'ಸಾಮಗ್ರಿ';

  @override
  String get kisanKhataNotLoaded => 'ಖಾತೆ ಪುಸ್ತಕ ಇನ್ನೂ ಈ ಫೋನ್‌ನಲ್ಲಿ ಇಲ್ಲ';

  @override
  String get kisanLess => 'ಕಡಿಮೆ';

  @override
  String get kisanMore => 'ಹೆಚ್ಚು';

  @override
  String get kisanMyCrops => 'ನನ್ನ ಬೆಳೆಗಳು';

  @override
  String get kisanMyOfficer => 'ನನ್ನ ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ';

  @override
  String get kisanMyOrders => 'ನನ್ನ ಆರ್ಡರ್‌ಗಳು';

  @override
  String get kisanNavCropDoctor => 'ಬೆಳೆ ವೈದ್ಯ';

  @override
  String get kisanNavHome => 'ಮುಖಪುಟ';

  @override
  String get kisanNavMe => 'ನಾನು';

  @override
  String get kisanNavOrders => 'ಆರ್ಡರ್‌ಗಳು';

  @override
  String get kisanNeedsInternet =>
      'ಇದಕ್ಕೆ ಇಂಟರ್ನೆಟ್ ಬೇಕು. ಇಂಟರ್ನೆಟ್ ಬಂದಾಗ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get kisanNextTaskSoon => 'ಮುಂದಿನ ಕೆಲಸ: ಶೀಘ್ರದಲ್ಲೇ';

  @override
  String get kisanNo => 'ಇಲ್ಲ';

  @override
  String get kisanNoAlerts => 'ನಿಮ್ಮ ಪ್ರದೇಶದಲ್ಲಿ ಕೀಟ ಎಚ್ಚರಿಕೆ ಇಲ್ಲ';

  @override
  String get kisanNoCropsHelp =>
      'ನಿಮ್ಮ ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ ಅಥವಾ ಅಂಗಡಿ ನಿಮ್ಮ ಹೊಲ ಸೇರಿಸಬಹುದು.';

  @override
  String get kisanNoCropsYet => 'ಇನ್ನೂ ಬೆಳೆಗಳಿಲ್ಲ';

  @override
  String get kisanNotifications => 'ಸೂಚನೆಗಳು';

  @override
  String get kisanNotPaidYet =>
      'ಇನ್ನೂ ಪಾವತಿ ಆಗಿಲ್ಲ. ನಂತರ ಅಥವಾ ಅಂಗಡಿಯಲ್ಲಿ ಪಾವತಿಸಬಹುದು.';

  @override
  String get kisanOff => 'ಆಫ್';

  @override
  String get kisanOffersOff => 'ಆಫರ್ ಮತ್ತು ಸಲಹೆ: ಆಫ್';

  @override
  String get kisanOffersOn => 'ಆಫರ್ ಮತ್ತು ಸಲಹೆ: ಆನ್';

  @override
  String get kisanOfficerPhoneMissing =>
      'ಅಧಿಕಾರಿಯ ಫೋನ್ ಇನ್ನೂ ಆ್ಯಪ್‌ನಲ್ಲಿ ಇಲ್ಲ. ನಿಮ್ಮ ಅಂಗಡಿಯಲ್ಲಿ ಕೇಳಿ.';

  @override
  String get kisanOn => 'ಆನ್';

  @override
  String get kisanOrderCollected => 'ಪಡೆದಿದ್ದೀರಿ';

  @override
  String get kisanOrderNotSaved => 'ಈ ಆರ್ಡರ್ ಇನ್ನೂ ಈ ಫೋನ್‌ನಲ್ಲಿ ಇಲ್ಲ';

  @override
  String get kisanOrderOnKhata => 'ನಿಮ್ಮ ಖಾತೆಯಲ್ಲಿ ಬರೆಯಲಾಗಿದೆ';

  @override
  String get kisanOrderPaid => 'ಪಾವತಿಸಲಾಗಿದೆ';

  @override
  String get kisanOrderPlaced => 'ಆರ್ಡರ್ ಮಾಡಲಾಗಿದೆ';

  @override
  String get kisanOrdersEmptyHelp =>
      'ಅಂಗಡಿಯಿಂದ ಆರ್ಡರ್ ಮಾಡಲು ಸಾಮಗ್ರಿ ಖರೀದಿಸಿ ಒತ್ತಿ.';

  @override
  String get kisanOrderShort =>
      'ಅಂಗಡಿಯಲ್ಲಿ ಒಂದು ಸಾಮಗ್ರಿ ಸಾಕಷ್ಟಿಲ್ಲ. ಪ್ರಮಾಣ ಬದಲಿಸಿ.';

  @override
  String get kisanOrderTitle => 'ನನ್ನ ಆರ್ಡರ್';

  @override
  String get kisanOutOfStock => 'ಈಗ ಸ್ಟಾಕ್ ಇಲ್ಲ';

  @override
  String kisanPaidOn(String time) {
    return '$timeರಂದು ಪಾವತಿ';
  }

  @override
  String get kisanPaidThanks => 'ಪಾವತಿ ಆಯಿತು. ಧನ್ಯವಾದ!';

  @override
  String get kisanPayAtStore => 'ಅಂಗಡಿಯಲ್ಲಿ ಪಾವತಿಸುತ್ತೇನೆ';

  @override
  String get kisanPayAtStoreHelp => 'ಸಾಮಗ್ರಿ ಪಡೆಯುವಾಗ ನಗದು ಅಥವಾ UPI';

  @override
  String get kisanPayAtStoreNote => 'ಪಡೆಯುವಾಗ ಅಂಗಡಿಯಲ್ಲಿ ಪಾವತಿಸಿ';

  @override
  String get kisanPayCredit => 'ಸಾಲ ಕೇಳಿ';

  @override
  String get kisanPaymentDone => 'ಪಾವತಿ ಸಿಕ್ಕಿದೆ';

  @override
  String get kisanPaymentFailed => 'ಪಾವತಿ ಆಗಲಿಲ್ಲ. ಹಣ ಕಡಿತವಾಗಿಲ್ಲ.';

  @override
  String kisanPaymentRef(String ref) {
    return 'ಉಲ್ಲೇಖ: $ref';
  }

  @override
  String get kisanPayTitle => 'ಪಾವತಿ';

  @override
  String get kisanPayUpi => 'UPI ಮೂಲಕ ಪಾವತಿಸಿ';

  @override
  String get kisanPayUpiHelp =>
      'PhonePe, Google Pay ಅಥವಾ ನಿಮ್ಮ UPI ಆ್ಯಪ್ ತೆರೆಯುತ್ತದೆ';

  @override
  String get kisanPickup => 'ಅಂಗಡಿಯಲ್ಲಿ ಪಡೆಯುತ್ತೇನೆ';

  @override
  String get kisanPickupQuestion => 'ಹೇಗೆ ಪಡೆಯುತ್ತೀರಿ?';

  @override
  String kisanPlacedOn(String time) {
    return '$timeರಂದು ಆರ್ಡರ್ ಮಾಡಿದ್ದು';
  }

  @override
  String get kisanPlaceOrder => 'ಆರ್ಡರ್ ಮಾಡಿ';

  @override
  String get kisanProductTitle => 'ಸಾಮಗ್ರಿ';

  @override
  String get kisanRateQuestion => 'ಭೇಟಿ ಹೇಗಿತ್ತು?';

  @override
  String get kisanRateTitle => 'ಭೇಟಿಗೆ ರೇಟಿಂಗ್ ಕೊಡಿ';

  @override
  String get kisanRateWhy => 'ಏಕೆ?';

  @override
  String get kisanReasonAdviceUnclear => 'ಸಲಹೆ ಅರ್ಥವಾಗಲಿಲ್ಲ';

  @override
  String get kisanReasonDidNotSeeCrop => 'ನನ್ನ ಬೆಳೆ ನೋಡಲಿಲ್ಲ';

  @override
  String get kisanReasonLookedAtCrop => 'ನನ್ನ ಬೆಳೆ ನೋಡಿದರು';

  @override
  String get kisanReasonOnTime => 'ಸಮಯಕ್ಕೆ ಬಂದರು';

  @override
  String get kisanReasonTooShort => 'ತುಂಬಾ ಕಡಿಮೆ ಹೊತ್ತು ಇದ್ದರು';

  @override
  String get kisanReasonUsefulAdvice => 'ಉಪಯುಕ್ತ ಸಲಹೆ';

  @override
  String get kisanReceiptTitle => 'ರಸೀದಿ';

  @override
  String get kisanSave => 'ಉಳಿಸಿ';

  @override
  String get kisanSaved => 'ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get kisanSavedWillSend => 'ಉಳಿಸಲಾಗಿದೆ. ಇಂಟರ್ನೆಟ್ ಬಂದಾಗ ಕಳುಹಿಸುತ್ತೇವೆ.';

  @override
  String get kisanSaveFailed => 'ಉಳಿಸಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get kisanScanButton => 'QR ಸ್ಕ್ಯಾನ್ ಮಾಡಿ';

  @override
  String get kisanScanHelp =>
      'ನಿಮ್ಮ ಫೀಲ್ಡ್ ಅಧಿಕಾರಿಗೆ ಅವರ ಫೋನ್‌ನಲ್ಲಿ QR ತೋರಿಸಲು ಹೇಳಿ, ನಂತರ ಅದನ್ನು ಸ್ಕ್ಯಾನ್ ಮಾಡಿ.';

  @override
  String get kisanScanNotVisitQr =>
      'ಇದು ಭೇಟಿಯ QR ಅಲ್ಲ. ಅಧಿಕಾರಿಯ ಫೋನ್‌ನಲ್ಲಿರುವ QR ಸ್ಕ್ಯಾನ್ ಮಾಡಿ.';

  @override
  String get kisanScanTitle => 'ಭೇಟಿ QR ಸ್ಕ್ಯಾನ್';

  @override
  String get kisanScanVisitQr => 'ಭೇಟಿ QR';

  @override
  String get kisanSend => 'ಕಳುಹಿಸಿ';

  @override
  String get kisanSetupCropQuestion => 'ಯಾವ ಬೆಳೆ ಬೆಳೆಯುತ್ತೀರಿ?';

  @override
  String get kisanSetupLandQuestion => 'ಎಷ್ಟು ಜಮೀನು?';

  @override
  String get kisanSetupNoVillages =>
      'ಊರುಗಳ ಪಟ್ಟಿ ಇನ್ನೂ ಈ ಫೋನ್‌ನಲ್ಲಿ ಇಲ್ಲ. ನಿಮ್ಮ ಅಂಗಡಿ ಸೇರಿಸುತ್ತದೆ.';

  @override
  String get kisanSetupSownQuestion => 'ಯಾವಾಗ ಬಿತ್ತಿದಿರಿ?';

  @override
  String get kisanSetupVillageQuestion => 'ನಿಮ್ಮ ಊರು';

  @override
  String get kisanShopEmptyHelp => 'ಬೇರೆ ರೀತಿಯ ಸಾಮಗ್ರಿ ನೋಡಿ.';

  @override
  String get kisanShopHelp =>
      'ಸಾಮಗ್ರಿ ನೋಡಲು ಮತ್ತು ಬುಟ್ಟಿಗೆ ಸೇರಿಸಲು ಅದನ್ನು ಒತ್ತಿ.';

  @override
  String get kisanSkipForNow => 'ಈಗ ಬಿಡಿ';

  @override
  String get kisanSoilQuestion => 'ನಿಮ್ಮ ಮಣ್ಣು ಯಾವುದು?';

  @override
  String get kisanSoilUnknown => 'ಮಣ್ಣು: ಗೊತ್ತಿಲ್ಲ';

  @override
  String get kisanSownLonger => '3 ತಿಂಗಳು ಅಥವಾ ಹೆಚ್ಚು';

  @override
  String get kisanSownThisMonth => 'ಈ ತಿಂಗಳು';

  @override
  String get kisanSownThisWeek => 'ಈ ವಾರ';

  @override
  String get kisanSownTwoMonths => '1–2 ತಿಂಗಳ ಹಿಂದೆ';

  @override
  String kisanStageIs(String stage) {
    return 'ಹಂತ: $stage';
  }

  @override
  String get kisanStageQuestion => 'ಬೆಳೆ ಯಾವ ಹಂತದಲ್ಲಿದೆ?';

  @override
  String get kisanStageUnknown => 'ಹಂತ: ಗೊತ್ತಿಲ್ಲ';

  @override
  String get kisanTotalEstimateNote => 'ಅಂತಿಮ ಬೆಲೆಯನ್ನು ಅಂಗಡಿ ಹೇಳುತ್ತದೆ.';

  @override
  String kisanTotalToPay(String amount) {
    return 'ಒಟ್ಟು $amount';
  }

  @override
  String get kisanUpiNoApp =>
      'ಯಾವ UPI ಆ್ಯಪ್ ತೆರೆಯಲಿಲ್ಲ. UPI ಆ್ಯಪ್ ಹಾಕಿ ಅಥವಾ ಅಂಗಡಿಯಲ್ಲಿ ಪಾವತಿಸಿ.';

  @override
  String get kisanUpiOpenAgain => 'UPI ಆ್ಯಪ್ ಮತ್ತೆ ತೆರೆಯಿರಿ';

  @override
  String get kisanUpiWaiting => 'ನಿಮ್ಮ UPI ಆ್ಯಪ್‌ನಲ್ಲಿ ಪಾವತಿ ಮುಗಿಸಿ';

  @override
  String get kisanViewCart => 'ಬುಟ್ಟಿ ನೋಡಿ';

  @override
  String get kisanVisitAlreadyAnswered => 'ಈ ಭೇಟಿಗೆ ಈಗಾಗಲೇ ಉತ್ತರಿಸಿದ್ದೀರಿ.';

  @override
  String get kisanVisitNoThanks => 'ಧನ್ಯವಾದ. ಅಧಿಕಾರಿಯೊಂದಿಗೆ ಪರಿಶೀಲಿಸುತ್ತೇವೆ.';

  @override
  String kisanVisitQuestion(String name) {
    return 'ಇಂದು $name ನಿಮ್ಮ ಹೊಲಕ್ಕೆ ಬಂದಿದ್ದರೆ?';
  }

  @override
  String get kisanVisitQuestionNoName =>
      'ಇಂದು ನಿಮ್ಮ ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ ನಿಮ್ಮ ಹೊಲಕ್ಕೆ ಬಂದಿದ್ದರೆ?';

  @override
  String get kisanVisitTapToAnswer => 'ಉತ್ತರಿಸಲು ಒತ್ತಿ';

  @override
  String get kisanVisitThanks => 'ಧನ್ಯವಾದ! ಭೇಟಿ ದೃಢಪಟ್ಟಿದೆ.';

  @override
  String get kisanVisitTitle => 'ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ ಭೇಟಿ';

  @override
  String get kisanVisitTokenInvalid =>
      'ಈ ಪ್ರಶ್ನೆಯ ಅವಧಿ ಮುಗಿದಿದೆ. ಅಧಿಕಾರಿಗೆ QR ತೋರಿಸಲು ಹೇಳಿ.';

  @override
  String get kisanWeatherSoon => 'ನಿಮ್ಮ ಹೊಲದ ಹವಾಮಾನ ಶೀಘ್ರದಲ್ಲೇ ಬರುತ್ತದೆ';

  @override
  String get kisanWelcomeChange => 'ಏನೋ ತಪ್ಪಿದೆ: ಬದಲಿಸಿ';

  @override
  String get kisanWelcomeConfirmHelp =>
      'ದಯವಿಟ್ಟು ನಿಮ್ಮ ಹೊಲ ಮತ್ತು ಬೆಳೆಗಳನ್ನು ನೋಡಿ.';

  @override
  String get kisanWelcomeCorrect => 'ಹೌದು, ಇದು ಸರಿ';

  @override
  String get kisanWelcomeEditHelp => 'ಬದಲಿಸಲು ಚಿತ್ರವನ್ನು ಒತ್ತಿ.';

  @override
  String kisanWelcomeFromOfficer(String name) {
    return '$name (ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ) ಅವರಿಂದ ನಿಮ್ಮ ಹೊಲದ ವಿವರ';
  }

  @override
  String get kisanWelcomeFromYourOfficer =>
      'ನಿಮ್ಮ ಫೀಲ್ಡ್ ಅಧಿಕಾರಿಯಿಂದ ನಿಮ್ಮ ಹೊಲದ ವಿವರ';

  @override
  String get kisanWelcomeTitle => 'ಸ್ವಾಗತ';

  @override
  String get kisanWhatsApp => 'WhatsApp';

  @override
  String get kisanYes => 'ಹೌದು';

  @override
  String get kisanYourOfficer => 'ನಿಮ್ಮ ಫೀಲ್ಡ್ ಅಧಿಕಾರಿ';

  @override
  String get photoTipNotPlant =>
      'ಕ್ಯಾಮೆರಾವನ್ನು ರೋಗದ ಎಲೆಯ ಕಡೆ ಹಿಡಿದು ಮತ್ತೆ ತೆಗೆಯಿರಿ';

  @override
  String get photoQualityNotPlant => 'ಎಲೆ ಕಾಣಲಿಲ್ಲ';

  @override
  String get treatmentPpeClothing => 'ಪೂರ್ಣ ತೋಳಿನ ಬಟ್ಟೆ';

  @override
  String get cropDoctorTitle => 'ಬೆಳೆ ವೈದ್ಯ';

  @override
  String get cropDoctorIntroTitle => 'ರೋಗದ ಎಲೆಯ ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get cropDoctorIntroTip1 => 'ಒಂದು ರೋಗದ ಎಲೆಯ ಹತ್ತಿರ ಹೋಗಿ';

  @override
  String get cropDoctorIntroTip2 => 'ಸೂರ್ಯ ನಿಮ್ಮ ಹಿಂದೆ ಇರುವಂತೆ ನಿಲ್ಲಿ';

  @override
  String get cropDoctorIntroTip3 =>
      'ಅಲುಗಾಡದೆ ಹಿಡಿದು ಎಲೆಯ ಮೇಲೆ ಒತ್ತಿ ಫೋಕಸ್ ಮಾಡಿ';

  @override
  String get cropDoctorUpTo3 => 'ನೀವು 3 ಫೋಟೋಗಳವರೆಗೆ ತೆಗೆಯಬಹುದು';

  @override
  String get cropDoctorOpenCamera => 'ಕ್ಯಾಮೆರಾ ತೆರೆಯಿರಿ';

  @override
  String get cropDoctorTakePhoto => 'ಫೋಟೋ ತೆಗೆಯಿರಿ';

  @override
  String get cropDoctorCameraDenied =>
      'ನಿಮ್ಮ ಬೆಳೆಯ ಫೋಟೋ ತೆಗೆಯಲು ಕ್ಯಾಮೆರಾಗೆ ಅನುಮತಿ ನೀಡಿ';

  @override
  String get cropDoctorCameraError => 'ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get cropDoctorTryAgain => 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ';

  @override
  String cropDoctorPhotoCount(int count) {
    return 'ಫೋಟೋ $count / 3';
  }

  @override
  String cropDoctorPhotosReady(int count) {
    return '3 ರಲ್ಲಿ $count ಫೋಟೋ ಸಿದ್ಧ';
  }

  @override
  String get cropDoctorAddPhoto => 'ಇನ್ನೊಂದು ಫೋಟೋ ಸೇರಿಸಿ';

  @override
  String get cropDoctorRemovePhoto => 'ಫೋಟೋ ತೆಗೆದುಹಾಕಿ';

  @override
  String get cropDoctorCheckCrop => 'ನನ್ನ ಬೆಳೆ ಪರೀಕ್ಷಿಸಿ';

  @override
  String get cropDoctorChooseCropTitle => 'ಇದು ಯಾವ ಬೆಳೆ?';

  @override
  String cropDoctorDetected(String crop) {
    return 'ಇದು $crop ತರಹ ಕಾಣುತ್ತದೆ. ತಪ್ಪಾದರೆ ಬೇರೆ ಬೆಳೆ ಒತ್ತಿ.';
  }

  @override
  String cropDoctorCropIs(String crop) {
    return 'ಬೆಳೆ: $crop';
  }

  @override
  String get cropDoctorChangeCrop => 'ಬೆಳೆ ಬದಲಿಸಿ';

  @override
  String get cropDoctorUnknownCrop => 'ನನಗೆ ಗೊತ್ತಿಲ್ಲ';

  @override
  String get cropDoctorAskExpertToo => 'ನಮ್ಮ ತಜ್ಞರನ್ನೂ ಕೇಳಿ';

  @override
  String get cropDoctorAnalysing => 'ನಿಮ್ಮ ಬೆಳೆಯನ್ನು ಪರೀಕ್ಷಿಸುತ್ತಿದ್ದೇವೆ…';

  @override
  String get cropDoctorAnalysingHelp => 'ಇದಕ್ಕೆ ಕೆಲವು ಸೆಕೆಂಡುಗಳು ಬೇಕು';

  @override
  String get cropDoctorQueuedTitle => 'ನಿಮ್ಮ ಫೋನ್‌ನಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ';

  @override
  String get cropDoctorQueuedHelp => 'ನಿಮಗೆ ಇಂಟರ್ನೆಟ್ ಸಿಕ್ಕಾಗ ಪರೀಕ್ಷಿಸುತ್ತೇವೆ';

  @override
  String get cropDoctorSendFailed =>
      'ನಿಮ್ಮ ಫೋಟೋ ಕಳುಹಿಸಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ತೆಗೆಯಿರಿ.';

  @override
  String get cropDoctorResultTitle => 'ಫಲಿತಾಂಶ';

  @override
  String get cropDoctorMessageAnswered => 'ಸಮಸ್ಯೆ ಪತ್ತೆಯಾಗಿದೆ';

  @override
  String get cropDoctorMessageProvisional =>
      'ತಾತ್ಕಾಲಿಕ — ತಜ್ಞರು ಖಚಿತಪಡಿಸುತ್ತಾರೆ';

  @override
  String get cropDoctorMessageUnknown =>
      'ಇನ್ನೂ ಖಚಿತವಿಲ್ಲ. ನಮ್ಮ ತಜ್ಞರು ನಿಮ್ಮ ಫೋಟೋ ನೋಡುತ್ತಾರೆ.';

  @override
  String get cropDoctorMessageConfirmed =>
      'ನಮ್ಮ ತಜ್ಞರು ಈ ಫಲಿತಾಂಶ ಖಚಿತಪಡಿಸಿದ್ದಾರೆ';

  @override
  String get cropDoctorMessageCorrected => 'ನಮ್ಮ ತಜ್ಞರು ಈ ಫಲಿತಾಂಶ ಬದಲಿಸಿದ್ದಾರೆ';

  @override
  String get cropDoctorOutNotPlant => 'ಫೋಟೋದಲ್ಲಿ ಗಿಡ ಕಾಣಲಿಲ್ಲ';

  @override
  String get cropDoctorOutUnsupportedCrop => 'ಈ ಬೆಳೆಯನ್ನು ಇನ್ನೂ ಪರೀಕ್ಷಿಸಲಾಗದು';

  @override
  String get cropDoctorOutUnreadable => 'ಫೋಟೋ ಸ್ಪಷ್ಟವಾಗಿಲ್ಲ';

  @override
  String get cropDoctorOutNoMatch => 'ಈ ಸಮಸ್ಯೆ ಪತ್ತೆಯಾಗಲಿಲ್ಲ';

  @override
  String get cropDoctorOutNotDiagnosable => 'ಫೋಟೋಗಳಿಂದ ತಜ್ಞರಿಗೆ ಹೇಳಲಾಗಲಿಲ್ಲ';

  @override
  String get cropDoctorOutHelp =>
      'ನಮ್ಮ ತಜ್ಞರು ಇದನ್ನು ನೋಡುತ್ತಾರೆ. ನಿಮ್ಮ ಫೀಲ್ಡ್ ಆಫೀಸರ್‌ಗೆ ಕರೆ ಮಾಡಬಹುದು.';

  @override
  String get cropDoctorTalkToOfficer => 'ನಿಮ್ಮ ಫೀಲ್ಡ್ ಆಫೀಸರ್ ಜೊತೆ ಮಾತನಾಡಿ';

  @override
  String get cropDoctorCallOfficer => 'ನನ್ನ ಆಫೀಸರ್‌ಗೆ ಕರೆ';

  @override
  String get cropDoctorAskExpert => 'ತಜ್ಞರನ್ನು ಕೇಳಿ';

  @override
  String get cropDoctorAskExpertSent =>
      'ನಮ್ಮ ತಜ್ಞರಿಗೆ ಕಳುಹಿಸಲಾಗಿದೆ. ಉತ್ತರ ತಿಳಿಸುತ್ತೇವೆ.';

  @override
  String get cropDoctorAskExpertAlready =>
      'ನಮ್ಮ ತಜ್ಞರ ಬಳಿ ಈಗಾಗಲೇ ನಿಮ್ಮ ಫೋಟೋಗಳಿವೆ';

  @override
  String get cropDoctorAskExpertFailed =>
      'ನಮ್ಮ ತಜ್ಞರನ್ನು ತಲುಪಲಾಗಲಿಲ್ಲ. ಇಂಟರ್ನೆಟ್ ನೋಡಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get cropDoctorOrder => 'ಆರ್ಡರ್ ಮಾಡಿ';

  @override
  String cropDoctorProductsAt(String store) {
    return '$store ನಲ್ಲಿ ಸಿಗುವವು';
  }

  @override
  String cropDoctorStoreDistance(String store, String km) {
    return '$store, $km ಕಿ.ಮೀ';
  }

  @override
  String get cropDoctorCulturalTitle => 'ಇದನ್ನೂ ಮಾಡಿ';

  @override
  String get cropDoctorNoProducts =>
      'ನಿಮ್ಮ ಅಂಗಡಿಯಲ್ಲಿ ಇದಕ್ಕೆ ಇನ್ನೂ ಉತ್ಪನ್ನವಿಲ್ಲ. ನಿಮ್ಮ ಫೀಲ್ಡ್ ಆಫೀಸರ್ ಜೊತೆ ಮಾತನಾಡಿ.';

  @override
  String get cropDoctorUpdatedTitle => 'ನಿಮ್ಮ ಫಲಿತಾಂಶ ನವೀಕರಿಸಲಾಗಿದೆ';

  @override
  String get cropDoctorHistoryTitle => 'ಹಿಂದಿನ ಉತ್ತರಗಳು';

  @override
  String cropDoctorEarlierAnswer(String answer) {
    return 'ಹಿಂದೆ: $answer';
  }

  @override
  String get cropDoctorMyChecks => 'ನನ್ನ ಬೆಳೆ ಪರೀಕ್ಷೆಗಳು';

  @override
  String get cropDoctorWaiting => 'ಉತ್ತರಕ್ಕಾಗಿ ಕಾಯುತ್ತಿದೆ';

  @override
  String get cropDoctorSymptomsHelp =>
      'ನಿಮ್ಮ ಬೆಳೆಯಲ್ಲಿ ಕಾಣುವ ಲಕ್ಷಣಗಳನ್ನು ಒತ್ತಿ';

  @override
  String cropDoctorResultUpdatedHome(String problem) {
    return 'ಬೆಳೆ ಪರೀಕ್ಷೆ ನವೀಕರಣ: $problem';
  }

  @override
  String get scoutTitle => 'ಬೆಳೆ ಪರಿಶೀಲನೆ';

  @override
  String get scoutChoosePlot => 'ಬೆಳೆ ಪ್ಲಾಟ್ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get scoutNoPlots =>
      'ಈ ರೈತರಿಗೆ ಇನ್ನೂ ಬೆಳೆ ಪ್ಲಾಟ್ ಇಲ್ಲ. ಮೊದಲು ಜಮೀನು, ಬೆಳೆ ಸೇರಿಸಿ.';

  @override
  String scoutPlotLine(String crop, String farm) {
    return '$crop · $farm';
  }

  @override
  String scoutAttachedTo(String farmer, String crop) {
    return '$farmer ಅವರಿಗಾಗಿ · $crop';
  }

  @override
  String get scoutCreateOrder => 'ರೈತರಿಗಾಗಿ ಆರ್ಡರ್ ಮಾಡಿ';

  @override
  String get scoutCallFarmer => 'ರೈತರಿಗೆ ಕರೆ';

  @override
  String get scoutQueuedHelp =>
      'ಸರದಿಯಲ್ಲಿದೆ. ಫೋನ್ ಆನ್‌ಲೈನ್ ಆದಾಗ ಕಳುಹಿಸಲಾಗುತ್ತದೆ.';

  @override
  String scoutProvenance(String model, String corpus) {
    return 'ಮಾದರಿ $model · ಕಾರ್ಪಸ್ v$corpus';
  }

  @override
  String get scoutNewDiagnosis => 'ಹೊಸ ರೋಗನಿರ್ಣಯ';

  @override
  String get scoutCheckPhotos => 'ಫೋಟೋ ಪರಿಶೀಲಿಸಿ';

  @override
  String get kisanDeleteStatusRejected =>
      'ನಿಮ್ಮ ವಿನಂತಿ ಸ್ವೀಕರಿಸಲಾಗಿಲ್ಲ. ದಯವಿಟ್ಟು ನಿಮ್ಮ ಅಂಗಡಿಗೆ ಕರೆ ಮಾಡಿ.';

  @override
  String get cropDoctorNotOnPhone => 'ಈ ಬೆಳೆ ಪರೀಕ್ಷೆ ಈ ಫೋನ್‌ನಲ್ಲಿ ಇಲ್ಲ';
}
