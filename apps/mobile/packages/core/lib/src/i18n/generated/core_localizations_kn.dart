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
}
