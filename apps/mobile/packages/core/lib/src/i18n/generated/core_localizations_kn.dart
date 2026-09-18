// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class CoreLocalizationsKn extends CoreLocalizations {
  CoreLocalizationsKn([String locale = 'kn']) : super(locale);

  @override
  String get appNameAgent => 'Mitra';

  @override
  String get appNameFarmer => 'Kisan';

  @override
  String get splashTagline => 'Trusted advice for your farm';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionBack => 'Back';

  @override
  String get actionNext => 'Next';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDone => 'Done';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionClose => 'Close';

  @override
  String get loading => 'Loading';

  @override
  String get languagePickerTitle => 'Choose your language';

  @override
  String get languagePickerSubtitle => 'Tap the speaker to hear it';

  @override
  String get languagePlayAudio => 'Listen';

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
  String get languageEnglishName => 'English';

  @override
  String get languageTeluguName => 'Telugu';

  @override
  String get languageKannadaName => 'Kannada';

  @override
  String get languageHindiName => 'Hindi';

  @override
  String get languageMarathiName => 'Marathi';

  @override
  String get phoneLoginTitle => 'Enter your mobile number';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'We will send a 6-digit OTP by SMS';

  @override
  String get phoneInvalid => 'Enter a valid 10-digit mobile number';

  @override
  String get phoneSendOtp => 'Send OTP';

  @override
  String get otpTitle => 'Enter the OTP';

  @override
  String otpSubtitle(String phone) {
    return 'Sent to +91 $phone';
  }

  @override
  String get otpLabel => '6-digit OTP';

  @override
  String get otpResend => 'Resend OTP';

  @override
  String otpResendIn(int seconds) {
    return 'Resend in $seconds s';
  }

  @override
  String get otpInvalid => 'Incorrect OTP. Please try again.';

  @override
  String get otpVerify => 'Verify';

  @override
  String otpDigitLabel(int index) {
    return 'Digit $index of 6';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count attempts left';
  }

  @override
  String otpLocked(int minutes) {
    return 'Too many wrong attempts. Try again in $minutes min.';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'Too many codes requested. Try again in $minutes min.';
  }

  @override
  String get otpExpired => 'This code has expired. Request a new one.';

  @override
  String get phoneNotFound =>
      'This number is not registered. Ask your manager to add you.';

  @override
  String get networkError => 'No connection. Check your network and try again.';

  @override
  String get consentTitle => 'Your location and data';

  @override
  String get consentPoint1 => 'We collect your location and visit photos.';

  @override
  String get consentPoint2 =>
      'Location is collected only while you are on duty.';

  @override
  String get consentPoint3 =>
      'It is used for travel allowance and visit credit.';

  @override
  String get consentPoint4 =>
      'Your manager and owner can see it. Farmers cannot.';

  @override
  String get consentAgree => 'I agree';

  @override
  String get consentPolicyLink => 'Read the full policy';

  @override
  String get consentDataCardTitle => 'Use my data to give crop advice';

  @override
  String get consentDataCardBody =>
      'We look at your crop photos and farm details to help you.';

  @override
  String get consentRequired => 'Required';

  @override
  String get consentOffersCardTitle => 'Send me offers and tips';

  @override
  String get consentOffersCardBody =>
      'Messages about products and farming tips.';

  @override
  String get consentOptional => 'Optional';

  @override
  String get consentReadAloud => 'Read aloud';

  @override
  String get dutyOn => 'On duty';

  @override
  String get dutyOff => 'Off duty';

  @override
  String get dutyGoOn => 'Go on duty';

  @override
  String get dutyGoOff => 'Go off duty';

  @override
  String dutyElapsed(String duration) {
    return 'On duty for $duration';
  }

  @override
  String get dutyLocationNote => 'Location is on only while you are on duty';

  @override
  String get syncSynced => 'Synced';

  @override
  String syncPending(int count) {
    return 'Pending $count';
  }

  @override
  String get syncFailed => 'Sync failed';

  @override
  String get offlineBanner =>
      'You are offline. Your work is saved and will sync later.';

  @override
  String get visitVerified => 'Verified';

  @override
  String get visitPartial => 'Partial';

  @override
  String get visitUnverified => 'Unverified';

  @override
  String visitScore(int score) {
    return 'Score $score of 100';
  }

  @override
  String visitDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get visitPurposeAdvisory => 'Advisory';

  @override
  String get visitPurposeScouting => 'Scouting';

  @override
  String get visitPurposeDemo => 'Demo';

  @override
  String get visitPurposeCollection => 'Collection';

  @override
  String get visitPurposeSale => 'Sale';

  @override
  String get visitPurposeMeeting => 'Meeting';

  @override
  String get proofGeofence => 'Inside farm boundary';

  @override
  String get proofGeofenceMissing => 'You were outside the farm boundary';

  @override
  String get proofPhoto => 'Photo taken';

  @override
  String get proofPhotoMissing => 'No photo taken during the visit';

  @override
  String get proofFarmerConfirmed => 'Farmer confirmed';

  @override
  String get proofFarmerConfirmedMissing => 'Farmer did not confirm the visit';

  @override
  String get proofDuration => 'Minimum time on farm met';

  @override
  String get proofDurationMissing => 'Visit was shorter than 10 minutes';

  @override
  String get proofDone => 'Done';

  @override
  String get proofMissing => 'Missing';

  @override
  String get cameraHoldSteady => 'Hold steady';

  @override
  String get cameraGoodLight => 'Good light';

  @override
  String get cameraFillFrame => 'Fill the frame';

  @override
  String get cameraLeafFrame => 'Place the leaf inside the frame';

  @override
  String get confidenceHigh => 'High confidence';

  @override
  String get confidenceMedium => 'Medium confidence';

  @override
  String get confidenceLow => 'Provisional';

  @override
  String get diagnosisSymptomsTitle => 'Check these signs';

  @override
  String get diagnosisProvisionalNote =>
      'Our expert will confirm within 24 hours';

  @override
  String get diagnosisProblem => 'Problem';

  @override
  String get treatmentOrganic => 'Organic';

  @override
  String get treatmentChemical => 'Chemical';

  @override
  String get treatmentActiveIngredient => 'Active ingredient';

  @override
  String get treatmentDosePerAcre => 'Per acre';

  @override
  String get treatmentDosePerTank => 'Per 15 L tank';

  @override
  String treatmentSafetyInterval(int days) {
    return 'Wait $days days before harvest';
  }

  @override
  String get treatmentPpeGloves => 'Gloves';

  @override
  String get treatmentPpeMask => 'Mask';

  @override
  String get treatmentPpeGoggles => 'Goggles';

  @override
  String get treatmentPpeTitle => 'Wear';

  @override
  String get ownBrand => 'Own brand';

  @override
  String get productAdd => 'Add';

  @override
  String get productAdded => 'Added';

  @override
  String productStockAtStore(int count, String store) {
    return '$count in stock at $store';
  }

  @override
  String get productOutOfStock => 'Out of stock';

  @override
  String get productPack => 'Pack';

  @override
  String cartItems(int count) {
    return '$count items';
  }

  @override
  String get cartTotal => 'Total';

  @override
  String get cartCheckout => 'Checkout';

  @override
  String get paymentMethodTitle => 'How will you pay?';

  @override
  String get paymentUpiQr => 'UPI QR';

  @override
  String get paymentUpiQrHint => 'Scan and pay now';

  @override
  String get paymentLink => 'Payment link';

  @override
  String get paymentLinkHint => 'Send by SMS or WhatsApp';

  @override
  String get paymentCash => 'Cash';

  @override
  String get paymentCashHint => 'Collect cash and give a receipt';

  @override
  String get paymentCredit => 'Credit';

  @override
  String get paymentCreditHint => 'Add to farmer khata';

  @override
  String get upiWaiting => 'Waiting for payment';

  @override
  String get upiPaid => 'Payment received';

  @override
  String get upiFailed => 'Payment failed';

  @override
  String upiExpiresIn(String time) {
    return 'Expires in $time';
  }

  @override
  String get upiAmount => 'Amount';

  @override
  String get upiScanHint => 'Ask the farmer to scan with any UPI app';

  @override
  String get upiRetry => 'Show a new QR';

  @override
  String get khataBalance => 'Balance due';

  @override
  String khataDueDate(String date) {
    return 'Due on $date';
  }

  @override
  String get khataDebit => 'Debit';

  @override
  String get khataCredit => 'Credit';

  @override
  String get khataNoEntries => 'No entries yet';

  @override
  String get khataPayNow => 'Pay now';

  @override
  String get khataCollect => 'Collect';

  @override
  String get emptyDefaultTitle => 'Nothing here yet';

  @override
  String get emptyDefaultHelp => 'Items will appear here once you add them.';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get errorHelp => 'Check your connection and try again.';

  @override
  String get ratingTitle => 'Rate your visit';

  @override
  String get rating1 => 'Very bad';

  @override
  String get rating2 => 'Bad';

  @override
  String get rating3 => 'Okay';

  @override
  String get rating4 => 'Good';

  @override
  String get rating5 => 'Very good';

  @override
  String stepperStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String farmerLastVisit(String date) {
    return 'Last visit $date';
  }

  @override
  String get farmerNoVisit => 'No visit yet';

  @override
  String farmerBalanceDue(String amount) {
    return 'Due $amount';
  }

  @override
  String get farmerVillage => 'Village';

  @override
  String get statTrendUp => 'Up';

  @override
  String get statTrendDown => 'Down';

  @override
  String get statTrendFlat => 'No change';

  @override
  String get stageSowing => 'Sowing';

  @override
  String get stageVegetative => 'Growing';

  @override
  String get stageFlowering => 'Flowering';

  @override
  String get stageFruiting => 'Fruiting';

  @override
  String get stageHarvest => 'Harvest';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSunlight => 'Sunlight';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get skeletonLoading => 'Loading content';
}
