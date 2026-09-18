// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class CoreLocalizationsTe extends CoreLocalizations {
  CoreLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get appNameAgent => 'మిత్ర';

  @override
  String get appNameFarmer => 'కిసాన్';

  @override
  String get splashTagline => 'మీ పొలానికి నమ్మకమైన సలహా';

  @override
  String get actionContinue => 'కొనసాగించు';

  @override
  String get actionBack => 'వెనుకకు';

  @override
  String get actionNext => 'తరువాత';

  @override
  String get actionRetry => 'మళ్ళీ ప్రయత్నించండి';

  @override
  String get actionCancel => 'రద్దు';

  @override
  String get actionDone => 'పూర్తి';

  @override
  String get actionSkip => 'దాటవేయి';

  @override
  String get actionClose => 'మూసివేయి';

  @override
  String get loading => 'లోడ్ అవుతోంది';

  @override
  String get languagePickerTitle => 'మీ భాషను ఎంచుకోండి';

  @override
  String get languagePickerSubtitle => 'వినడానికి స్పీకర్‌ను నొక్కండి';

  @override
  String get languagePlayAudio => 'వినండి';

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
  String get languageEnglishName => 'ఇంగ్లీష్';

  @override
  String get languageTeluguName => 'తెలుగు';

  @override
  String get languageKannadaName => 'కన్నడ';

  @override
  String get languageHindiName => 'హిందీ';

  @override
  String get languageMarathiName => 'మరాఠీ';

  @override
  String get phoneLoginTitle => 'మీ మొబైల్ నంబర్ నమోదు చేయండి';

  @override
  String get phoneLabel => 'మొబైల్ నంబర్';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'మేము SMS ద్వారా 6 అంకెల OTP పంపుతాము';

  @override
  String get phoneInvalid => 'సరైన 10 అంకెల మొబైల్ నంబర్ నమోదు చేయండి';

  @override
  String get phoneSendOtp => 'OTP పంపండి';

  @override
  String get otpTitle => 'OTP నమోదు చేయండి';

  @override
  String otpSubtitle(String phone) {
    return '+91 $phone కు పంపబడింది';
  }

  @override
  String get otpLabel => '6 అంకెల OTP';

  @override
  String get otpResend => 'OTP మళ్ళీ పంపండి';

  @override
  String otpResendIn(int seconds) {
    return '$seconds సెకన్లలో మళ్ళీ పంపండి';
  }

  @override
  String get otpInvalid => 'OTP తప్పు. మళ్ళీ ప్రయత్నించండి.';

  @override
  String get otpVerify => 'ధృవీకరించు';

  @override
  String otpDigitLabel(int index) {
    return '6లో $indexవ అంకె';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count ప్రయత్నాలు మిగిలాయి';
  }

  @override
  String otpLocked(int minutes) {
    return 'చాలా తప్పు ప్రయత్నాలు. $minutes నిమిషాల తర్వాత మళ్ళీ ప్రయత్నించండి.';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'చాలా సార్లు OTP అడిగారు. $minutes నిమిషాల తర్వాత మళ్ళీ ప్రయత్నించండి.';
  }

  @override
  String get otpExpired => 'ఈ OTP గడువు ముగిసింది. కొత్తది అడగండి.';

  @override
  String get phoneNotFound =>
      'ఈ నంబర్ నమోదు కాలేదు. మిమ్మల్ని జోడించమని మీ మేనేజర్‌ను అడగండి.';

  @override
  String get networkError =>
      'కనెక్షన్ లేదు. మీ నెట్‌వర్క్ తనిఖీ చేసి మళ్ళీ ప్రయత్నించండి.';

  @override
  String get consentTitle => 'మీ లొకేషన్ మరియు డేటా';

  @override
  String get consentPoint1 =>
      'మేము మీ లొకేషన్ మరియు సందర్శన ఫోటోలను సేకరిస్తాము.';

  @override
  String get consentPoint2 =>
      'మీరు డ్యూటీలో ఉన్నప్పుడు మాత్రమే లొకేషన్ సేకరిస్తాము.';

  @override
  String get consentPoint3 =>
      'ఇది ప్రయాణ భత్యం మరియు సందర్శన క్రెడిట్ కోసం ఉపయోగిస్తాము.';

  @override
  String get consentPoint4 =>
      'మీ మేనేజర్ మరియు యజమాని చూడగలరు. రైతులు చూడలేరు.';

  @override
  String get consentAgree => 'నేను అంగీకరిస్తున్నాను';

  @override
  String get consentPolicyLink => 'పూర్తి విధానం చదవండి';

  @override
  String get consentDataCardTitle => 'పంట సలహా ఇవ్వడానికి నా డేటాను వాడండి';

  @override
  String get consentDataCardBody =>
      'మీకు సహాయం చేయడానికి మీ పంట ఫోటోలు, పొలం వివరాలు చూస్తాము.';

  @override
  String get consentRequired => 'తప్పనిసరి';

  @override
  String get consentOffersCardTitle => 'నాకు ఆఫర్లు మరియు సలహాలు పంపండి';

  @override
  String get consentOffersCardBody =>
      'ఉత్పత్తులు మరియు వ్యవసాయ సలహాల గురించి సందేశాలు.';

  @override
  String get consentOptional => 'ఐచ్ఛికం';

  @override
  String get consentReadAloud => 'చదివి వినిపించు';

  @override
  String get dutyOn => 'డ్యూటీలో ఉన్నారు';

  @override
  String get dutyOff => 'డ్యూటీలో లేరు';

  @override
  String get dutyGoOn => 'డ్యూటీ ప్రారంభించు';

  @override
  String get dutyGoOff => 'డ్యూటీ ముగించు';

  @override
  String dutyElapsed(String duration) {
    return '$duration నుండి డ్యూటీలో';
  }

  @override
  String get dutyLocationNote =>
      'మీరు డ్యూటీలో ఉన్నప్పుడు మాత్రమే లొకేషన్ ఆన్‌లో ఉంటుంది';

  @override
  String get syncSynced => 'సింక్ అయింది';

  @override
  String syncPending(int count) {
    return '$count పెండింగ్';
  }

  @override
  String get syncFailed => 'సింక్ విఫలమైంది';

  @override
  String get offlineBanner =>
      'మీరు ఆఫ్‌లైన్‌లో ఉన్నారు. మీ పని సేవ్ అయింది, తర్వాత సింక్ అవుతుంది.';

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
  String get settingsTheme => 'థీమ్';

  @override
  String get themeLight => 'లైట్';

  @override
  String get themeSunlight => 'ఎండ';

  @override
  String get settingsTitle => 'సెట్టింగ్‌లు';

  @override
  String get skeletonLoading => 'Loading content';
}
