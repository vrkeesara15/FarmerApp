// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class CoreLocalizationsEn extends CoreLocalizations {
  CoreLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get syncSyncing => 'Syncing…';

  @override
  String get syncDetailsTitle => 'Sync details';

  @override
  String get syncNow => 'Sync now';

  @override
  String syncLastSync(String time) {
    return 'Last synced $time';
  }

  @override
  String get syncNeverSynced => 'Not synced yet';

  @override
  String get syncAllDone => 'Everything is synced';

  @override
  String get syncAllDoneHelp =>
      'New farmers, farms and photos saved offline appear here until they reach the server.';

  @override
  String syncPendingSection(int count) {
    return 'Waiting to sync ($count)';
  }

  @override
  String syncFailedSection(int count) {
    return 'Needs attention ($count)';
  }

  @override
  String get syncWaitingForPhoto => 'Waiting for the photo to upload';

  @override
  String syncPhotoUploads(int count) {
    return 'Photos uploading: $count';
  }

  @override
  String get syncTransportError =>
      'Could not reach the server. It will try again on its own.';

  @override
  String syncNextAttempt(String time) {
    return 'Next attempt $time';
  }

  @override
  String syncItemTitle(String action, String entity) {
    return '$action $entity';
  }

  @override
  String get syncActionCreate => 'New';

  @override
  String get syncActionUpdate => 'Edited';

  @override
  String get syncActionDelete => 'Deleted';

  @override
  String get syncEntityFarmer => 'farmer';

  @override
  String get syncEntityFarm => 'farm';

  @override
  String get syncEntityCropPlot => 'crop plot';

  @override
  String get syncEntityConsent => 'consent';

  @override
  String get syncEntityOther => 'item';

  @override
  String syncSavedAt(String time) {
    return 'Saved $time';
  }

  @override
  String get syncRejectedDefault =>
      'The server did not accept this item. Edit it and retry.';

  @override
  String get syncRetryAll => 'Retry all';

  @override
  String get syncDiscard => 'Discard';

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
  String get photoReviewHeading => 'Check your photo';

  @override
  String photoReviewTitle(int index, int total) {
    return 'Photo $index of $total';
  }

  @override
  String get photoQualityOk => 'Good photo';

  @override
  String get photoQualityBlurry => 'Blurry';

  @override
  String get photoQualityDark => 'Too dark';

  @override
  String get photoQualityChecking => 'Checking photo';

  @override
  String get photoTipBlurry =>
      'Hold the phone steady, tap the leaf to focus and take it again';

  @override
  String get photoTipDark =>
      'Move into better light, away from shade, and take it again';

  @override
  String get photoTipOk => 'Photo looks good';

  @override
  String get photoRetake => 'Retake';

  @override
  String get photoUse => 'Use photo';

  @override
  String photoSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String photoDimensions(int width, int height) {
    return '$width × $height px';
  }

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
  String get settingsLanguage => 'Language';

  @override
  String get skeletonLoading => 'Loading content';

  @override
  String get farmersTitle => 'Farmers';

  @override
  String get farmersSearchHint => 'Search name, phone or village';

  @override
  String get farmersAddFarmer => 'Add farmer';

  @override
  String get farmersEmptyTitle => 'No farmers yet';

  @override
  String get farmersEmptyHelp =>
      'Add your first farmer to start visits and orders.';

  @override
  String get farmersNoResults => 'No farmers match your search';

  @override
  String get farmersFilterVillage => 'Village';

  @override
  String get farmersFilterCrop => 'Crop';

  @override
  String get farmersFilterAll => 'All';

  @override
  String farmersCount(int count) {
    return '$count farmers';
  }

  @override
  String get farmerPendingSync => 'Will sync when online';

  @override
  String get farmerPhoneUnverified => 'Phone not verified';

  @override
  String get farmerRejected => 'Needs attention';

  @override
  String get regTitle => 'Add farmer';

  @override
  String get regStepBasics => 'Farmer details';

  @override
  String get regStepBoundary => 'Farm boundary';

  @override
  String get regStepCrops => 'Crops';

  @override
  String get regStepConsent => 'Consent';

  @override
  String get regStepReview => 'Review and save';

  @override
  String get regResumeDraft => 'Continuing where you left off';

  @override
  String get regDiscardDraft => 'Discard draft';

  @override
  String get regFixIssues => 'Fix the highlighted fields to continue';

  @override
  String get regNameLabel => 'Farmer name';

  @override
  String get regNameHint => 'As on the ID card';

  @override
  String get regPhoneLabel => 'Farmer mobile number';

  @override
  String get regPhoneHelper => 'An OTP will be sent to the farmer';

  @override
  String get regSendOtpToFarmer => 'Send OTP to farmer';

  @override
  String get regOtpSent => 'OTP sent to the farmer. Ask them for the code.';

  @override
  String get regPhoneVerified => 'Phone verified';

  @override
  String get regVerifyLater => 'Verify later';

  @override
  String get regVerifyLaterNote =>
      'No signal? Save now and verify the phone from the farmer profile.';

  @override
  String get regVerifyLaterChosen => 'Will be verified later';

  @override
  String get regDuplicatePhone => 'A farmer with this number already exists';

  @override
  String get regDuplicateOpen => 'Open existing farmer';

  @override
  String get regVillageLabel => 'Village';

  @override
  String get regVillageHint => 'Choose the village';

  @override
  String get regVillageTyped => 'Village name';

  @override
  String get regVillageNoneSynced =>
      'Villages will load after the first sync. Type the village name for now.';

  @override
  String get regLandmarkLabel => 'Landmark';

  @override
  String get regLandmarkHint => 'Near the temple, school…';

  @override
  String get regLanguageLabel => 'Language of the farmer';

  @override
  String get regOwnershipLabel => 'Land';

  @override
  String get regBoundaryWalk => 'Walk around';

  @override
  String get regBoundaryTap => 'Tap corners';

  @override
  String get regStartWalk => 'Start walking';

  @override
  String get regStopWalk => 'Pause';

  @override
  String get regClosePolygon => 'Close boundary';

  @override
  String get regUndoPoint => 'Undo point';

  @override
  String get regClearBoundary => 'Clear';

  @override
  String regPointsCount(int count) {
    return '$count points';
  }

  @override
  String regAccuracy(int metres) {
    return 'GPS accuracy ±$metres m';
  }

  @override
  String get regAccuracyWaiting => 'Waiting for GPS…';

  @override
  String get regLocationOff => 'Turn on location to walk the boundary';

  @override
  String get regLocationDenied =>
      'Location permission is needed to walk the boundary';

  @override
  String get regTapHint => 'Tap the four corners of the farm on the map';

  @override
  String get regWalkHint =>
      'Walk along the edge of the farm. Points are added as you go.';

  @override
  String regComputedArea(String acres) {
    return 'Measured area $acres acres';
  }

  @override
  String get regAreaLabel => 'Area in acres';

  @override
  String get regAreaHint => 'As the farmer says';

  @override
  String get regUseMeasured => 'Use measured';

  @override
  String get regAreaWarning =>
      'The entered area differs from the measured area by more than 30%. Check it before saving.';

  @override
  String get regBoundaryInvalid =>
      'The boundary crosses itself. Undo the last points and try again.';

  @override
  String get regFarmNameLabel => 'Farm name (optional)';

  @override
  String get regFarmNameHint => 'Home farm';

  @override
  String get regSoilLabel => 'Soil type';

  @override
  String get regIrrigationLabel => 'Irrigation';

  @override
  String get regFarmPhoto => 'Farm photo (optional)';

  @override
  String get regTakePhoto => 'Take photo';

  @override
  String get regPhotoAdded => 'Photo added';

  @override
  String get regPhotoRemove => 'Remove';

  @override
  String regFarmPhotosCount(int count) {
    return '$count photos';
  }

  @override
  String get regCropsHelp => 'Add every crop growing on this farm this season.';

  @override
  String get regAddCrop => 'Add crop';

  @override
  String get regCropLabel => 'Crop';

  @override
  String get regVarietyLabel => 'Variety';

  @override
  String get regVarietyHint => 'e.g. MTU-1010';

  @override
  String get regSowingDateLabel => 'Sowing date';

  @override
  String get regSowingDateHint => 'DD-MM-YYYY';

  @override
  String regSeasonAuto(String season) {
    return 'Season: $season';
  }

  @override
  String get regPlotAreaLabel => 'Area (acres, optional)';

  @override
  String get regRemoveCrop => 'Remove crop';

  @override
  String regPlotTitle(int index) {
    return 'Crop $index';
  }

  @override
  String get regAddFarm => 'Add another farm';

  @override
  String regFarmsCount(int count) {
    return '$count farms';
  }

  @override
  String regFarmIndex(int index) {
    return 'Farm $index';
  }

  @override
  String get regConsentIntro => 'Read this to the farmer in their language.';

  @override
  String get regConsentNotice =>
      'We will keep your name, phone, village and farm details to give you crop advice and keep visit records. You can ask us to stop at any time.';

  @override
  String get regConsentMarketingNotice =>
      'With your permission we will also send offers and farming tips by SMS or WhatsApp.';

  @override
  String get regConsentGiven => 'Farmer agrees';

  @override
  String get regReviewFarmer => 'Farmer';

  @override
  String get regReviewFarms => 'Farms and crops';

  @override
  String get regReviewConsent => 'Consent';

  @override
  String get regReviewSyncNote =>
      'Saved on this phone now; sent to the server when the network is back.';

  @override
  String get regSave => 'Save farmer';

  @override
  String get regSaveFarm => 'Save farm';

  @override
  String get regEdit => 'Edit';

  @override
  String get regSaved => 'Farmer saved';

  @override
  String get regIssueName => 'Enter the farmer name';

  @override
  String get regIssuePhoneUnverified =>
      'Verify the phone or choose Verify later';

  @override
  String get regIssueVillage => 'Choose the village';

  @override
  String get regIssueLanguage => 'Choose the language of the farmer';

  @override
  String get regIssueBoundary => 'Mark at least 3 points of the boundary';

  @override
  String get regIssueArea => 'Enter the area in acres';

  @override
  String get regIssueCrop => 'Add at least one crop';

  @override
  String get regIssueSowingDate => 'Enter the sowing date for every crop';

  @override
  String get regIssueConsent => 'Data consent is required to register';

  @override
  String get soilBlack => 'Black';

  @override
  String get soilRed => 'Red';

  @override
  String get soilSandy => 'Sandy';

  @override
  String get soilLoamy => 'Loamy';

  @override
  String get soilClay => 'Clay';

  @override
  String get soilAlluvial => 'Alluvial';

  @override
  String get soilLaterite => 'Laterite';

  @override
  String get irrigationRainfed => 'Rainfed';

  @override
  String get irrigationBorewell => 'Borewell';

  @override
  String get irrigationCanal => 'Canal';

  @override
  String get irrigationTank => 'Tank';

  @override
  String get irrigationOpenWell => 'Open well';

  @override
  String get irrigationDrip => 'Drip';

  @override
  String get irrigationSprinkler => 'Sprinkler';

  @override
  String get ownershipOwn => 'Own';

  @override
  String get ownershipLeased => 'Leased';

  @override
  String get seasonKharif => 'Kharif';

  @override
  String get seasonRabi => 'Rabi';

  @override
  String get seasonZaid => 'Zaid (summer)';

  @override
  String get profileTabOverview => 'Overview';

  @override
  String get profileTabVisits => 'Visits';

  @override
  String get profileTabDiagnoses => 'Diagnoses';

  @override
  String get profileTabOrders => 'Orders';

  @override
  String get profileTabKhata => 'Khata';

  @override
  String get profileStartVisit => 'Start visit';

  @override
  String get profileScout => 'Scout';

  @override
  String get profileNewOrder => 'New order';

  @override
  String get profileCollect => 'Collect';

  @override
  String get profileComingSoon => 'Coming in a later update';

  @override
  String get profileVisitsEmpty => 'No visits yet';

  @override
  String get profileDiagnosesEmpty => 'No diagnoses yet';

  @override
  String get profileOrdersEmpty => 'No orders yet';

  @override
  String get profileKhataEmpty => 'No khata entries yet';

  @override
  String get profilePhone => 'Phone';

  @override
  String get profileLandmark => 'Landmark';

  @override
  String get profileLanguage => 'Language';

  @override
  String get profileOwnership => 'Land';

  @override
  String get profileFarms => 'Farms';

  @override
  String profileAcres(String acres) {
    return '$acres acres';
  }

  @override
  String get profileAddFarm => 'Add farm';

  @override
  String get profileEditFarm => 'Edit farm';

  @override
  String profileFarmPlots(int count) {
    return '$count crops';
  }

  @override
  String get profileNoFarms => 'No farms yet';

  @override
  String get profileDuplicateTitle => 'Duplicate — merge?';

  @override
  String get profileDuplicateBody =>
      'The server already has a farmer with this number. Open the existing record and merge the details.';

  @override
  String get profileRejectedTitle => 'Sync rejected';

  @override
  String get profileRejectedHelp => 'Open Sync details to fix and retry.';

  @override
  String get profileNotFound => 'Farmer not found';

  @override
  String get profileVerifyPhone => 'Verify phone';

  @override
  String get consentGiven => 'Given';

  @override
  String get consentNotGiven => 'Not given';

  @override
  String get farmEditTitle => 'Edit farm';

  @override
  String get farmAddTitle => 'Add farm';

  @override
  String get mapNoBoundary => 'No boundary yet';

  @override
  String get mapAttribution => '© OpenStreetMap contributors';

  @override
  String get mapCurrentPosition => 'Your position';

  @override
  String mapCorner(int index) {
    return 'Corner $index';
  }

  @override
  String get mapFarmBoundary => 'Farm boundary';

  @override
  String get dutyNotificationTitle => 'On duty — location on';

  @override
  String get dutyChannelName => 'Duty';

  @override
  String get dutyAlertsChannelName => 'Duty alerts';

  @override
  String get dutyPromptTitle => 'Still on duty?';

  @override
  String dutyPromptBody(String time) {
    return 'Ending at $time';
  }

  @override
  String get dutyEndedTitle => 'Duty ended';

  @override
  String dutyAutoEndedBody(String time) {
    return 'Your day ended automatically at $time.';
  }

  @override
  String get dutyServerEndedBody =>
      'Your duty was ended by the server (idle or end of day).';

  @override
  String dutyAutoEndAt(String time) {
    return 'Ends automatically at $time';
  }

  @override
  String get dutyBlockedPolicy => 'Accept the location policy to go on duty';

  @override
  String get dutyReviewPolicy => 'Review policy';

  @override
  String dutyPointsPending(int count) {
    return '$count points waiting to upload';
  }

  @override
  String get dutyNoticeAlreadyActive =>
      'You are already on duty on another device. This one stays off.';

  @override
  String get dutyNoticePolicy =>
      'Please accept the current location policy before going on duty.';

  @override
  String get dutyNoticeLocationUnavailable =>
      'Could not get your location. Turn on location and try again.';

  @override
  String get integrityBanner =>
      'Some device checks reported issues; visits may be reviewed.';

  @override
  String get disclosureIntro =>
      'Before you start, here is what Mitra records and why.';

  @override
  String disclosureVersion(String version) {
    return 'Policy version $version';
  }

  @override
  String get disclosureUpdated =>
      'The location policy has changed. Please read and accept the new version.';

  @override
  String get policySheetTitle => 'Location policy';

  @override
  String get locationPolicyText =>
      'Mitra location policy (version 2026-09-v1)\n\n1. What we collect. While you are on duty, Mitra records your location (latitude, longitude, accuracy, speed, direction), the time, your battery level and basic device checks (mock-location, rooted device, clock difference). It also records the photos, notes and farmer confirmations you capture during visits.\n\n2. Only while on duty. Location is recorded only after you switch duty on, and it stops the moment you switch duty off, when the day ends at the tenant’s set time (20:00 by default) or after 60 minutes idle at your home location. Nothing is recorded while you are off duty, and a notification is always visible while location is on.\n\n3. Why we collect it. Your track computes the kilometres for your travel allowance, and your location at a visit gives you credit for that visit. No track means no automatic travel allowance and no verified visit.\n\n4. Who can see it. Your cluster head, the directors and the owner of your organisation can see your track and visits for their area, and auditors can review flagged visits. Store managers and farmers never see your location. Raw points are kept for 180 days and then reduced to daily totals.';

  @override
  String get permissionsTitle => 'Permissions Mitra needs';

  @override
  String get permissionsIntro =>
      'Mitra asks for these one by one. You can change them later in Settings.';

  @override
  String get permLocationTitle => 'Location';

  @override
  String get permLocationBody =>
      'To record your track while on duty and check you are at the farm.';

  @override
  String get permBackgroundTitle => 'Location all the time';

  @override
  String get permBackgroundBody =>
      'Choose \"Allow all the time\" so tracking continues while the screen is off. It still runs only while you are on duty.';

  @override
  String get permCameraTitle => 'Camera';

  @override
  String get permCameraBody =>
      'For farm and visit photos taken inside the app.';

  @override
  String get permNotificationsTitle => 'Notifications';

  @override
  String get permNotificationsBody =>
      'To show the on-duty notice and remind you before duty ends.';

  @override
  String get permGranted => 'Allowed';

  @override
  String get permDenied => 'Not allowed';

  @override
  String get permOpenSettings => 'Open settings';

  @override
  String get permAllow => 'Allow';

  @override
  String get registeredTitle => 'Device registered';

  @override
  String get registeredBody =>
      'You are set. Go on duty from Home to start your day.';

  @override
  String get registeredStart => 'Go to Home';

  @override
  String get homeTitle => 'Home';

  @override
  String get homeTodayStats => 'Today';

  @override
  String get statVisitsVerified => 'Visits verified';

  @override
  String get statFarmersAdded => 'Farmers added';

  @override
  String get statCollections => 'Collections';

  @override
  String get homeNextUp => 'Next up';

  @override
  String get homeNextUpEmpty => 'No beat plan yet';

  @override
  String get homeNextUpEmptyHelp =>
      'Your cluster head will assign villages. Until then, add farmers and start visits.';

  @override
  String get homeQuickActions => 'Quick actions';

  @override
  String get actionStartVisit => 'Start visit';

  @override
  String get actionScoutCrop => 'Scout crop';

  @override
  String get actionCollectPayment => 'Collect payment';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get navHome => 'Home';

  @override
  String get navFarmers => 'Farmers';

  @override
  String get navVisits => 'Visits';

  @override
  String get navOrders => 'Orders';

  @override
  String get navMe => 'Me';

  @override
  String get myDayTitle => 'My day';

  @override
  String myDayKm(String km) {
    return '$km km today';
  }

  @override
  String get myDayEmpty => 'No duty today yet';

  @override
  String get myDayEmptyHelp =>
      'Go on duty from Home; your track and km appear here.';

  @override
  String myDaySession(String start, String end) {
    return 'Duty $start – $end';
  }

  @override
  String myDaySessionActive(String start) {
    return 'Duty since $start';
  }

  @override
  String myDayPoints(int pending, int accepted) {
    return '$pending pending · $accepted accepted';
  }

  @override
  String get myDayGapsTitle => 'Gaps and reasons';

  @override
  String get myDayGapsHelp => 'Gap reasons arrive with the next update.';

  @override
  String get myDayEndReasonManual => 'Ended by you';

  @override
  String get myDayEndReasonAutoTime => 'Ended at day end';

  @override
  String get myDayEndReasonAutoIdle => 'Ended after idle';

  @override
  String get myDayEndReasonForced => 'Ended by manager';

  @override
  String get myDayEndReasonRejected => 'Not recorded';

  @override
  String get syncEntityDutySession => 'Duty session';

  @override
  String get syncEntityLocationBatch => 'Location points';

  @override
  String get syncEntityPolicyAcceptance => 'Policy acceptance';

  @override
  String get visitsTitle => 'Visits';

  @override
  String get visitsTabToday => 'Today';

  @override
  String get visitsTabWeek => 'This week';

  @override
  String get visitsFilterAll => 'All';

  @override
  String get visitsEmptyTitle => 'No visits yet';

  @override
  String get visitsEmptyHelp =>
      'Start a visit from a farmer profile or with the button below.';

  @override
  String get visitStatusOpen => 'In progress';

  @override
  String get visitCardPending => 'Will sync when online';

  @override
  String get visitCardFailed => 'Needs attention';

  @override
  String get visitChooseFarmer => 'Choose a farmer';

  @override
  String get visitFarmLabel => 'Farm';

  @override
  String get visitFarmNoBoundary => 'No boundary recorded for this farm';

  @override
  String get visitPurposeLabel => 'Purpose';

  @override
  String get visitOffDutyTitle => 'Go on duty first';

  @override
  String get visitOffDutyBody =>
      'Visits are recorded only while you are on duty. Switch duty on from Home and come back.';

  @override
  String get visitGoHome => 'Go to Home';

  @override
  String get visitLocating => 'Getting your location…';

  @override
  String get visitNoFix =>
      'Could not get your location. Move under open sky and try again.';

  @override
  String get visitRefreshLocation => 'Check location again';

  @override
  String visitAccuracy(int metres) {
    return 'Accuracy ±$metres m';
  }

  @override
  String get visitInsideGeofence => 'You are inside the farm geofence';

  @override
  String get visitAtMeetingPoint => 'You are at the village meeting point';

  @override
  String visitOutsideFarm(int distance, int radius) {
    return '$distance m from the farm boundary; the geofence is $radius m.';
  }

  @override
  String visitOutsideMeeting(int distance, int radius) {
    return '$distance m from the meeting point; the allowed radius is $radius m.';
  }

  @override
  String get visitNoTarget =>
      'This farm has no boundary and the village has no meeting point. Check in with an override note.';

  @override
  String get visitRequestOverride => 'Request override';

  @override
  String get visitOverrideNoteLabel => 'Why are you checking in from here?';

  @override
  String get visitOverrideNoteHint => 'e.g. Met the farmer at the market';

  @override
  String get visitOverrideNoteRequired => 'Add a note to request an override';

  @override
  String get visitOverrideHelp =>
      'Your cluster head reviews the override. The visit earns geofence credit only if it is approved.';

  @override
  String get visitCheckIn => 'Check in';

  @override
  String get visitCheckInOverride => 'Check in with override';

  @override
  String get visitInProgress => 'Visit in progress';

  @override
  String get visitTimerLabel => 'Time on visit';

  @override
  String visitMinDuration(int minutes) {
    return 'Minimum $minutes min';
  }

  @override
  String visitDurationNeeds(int minutes, int minimum) {
    return '$minutes min of $minimum min';
  }

  @override
  String visitUnderMinimum(int minutes) {
    return 'Under the minimum of $minutes min. The visit is flagged, not rejected.';
  }

  @override
  String get visitPhotos => 'Photos';

  @override
  String get visitTakePhoto => 'Take photo';

  @override
  String visitPhotoCount(int count) {
    return '$count photos';
  }

  @override
  String get visitPhotosHelp =>
      'In-app camera only. Take at least one photo at the farm.';

  @override
  String get visitNotesLabel => 'Notes';

  @override
  String get visitNotesHint => 'What did you observe or advise?';

  @override
  String get visitCropStageLabel => 'Crop stage';

  @override
  String get cropStageSown => 'Sown';

  @override
  String get cropStageMaturity => 'Maturity';

  @override
  String get cropStageHarvested => 'Harvested';

  @override
  String get visitProofTitle => 'Proof of visit';

  @override
  String get visitExpectedScore => 'Expected score';

  @override
  String get visitServerScore => 'Score from the server';

  @override
  String get visitConfirmFarmer => 'Farmer confirmation';

  @override
  String get visitCheckOut => 'Check out';

  @override
  String get visitCheckInPending => 'Check-in will sync when online';

  @override
  String get visitCheckInSynced => 'Check-in synced';

  @override
  String get visitRejectedTitle => 'Check-in refused';

  @override
  String visitRejectedOutside(int distance) {
    return 'The server placed you $distance m outside the geofence.';
  }

  @override
  String get visitRejectedNoTarget =>
      'The server found nothing to check your location against.';

  @override
  String get visitRetryFromFarm => 'Retry from the farm';

  @override
  String visitRetryStillOutside(int distance) {
    return 'Still $distance m outside. Move closer or request an override.';
  }

  @override
  String get visitRetryQueued =>
      'Check-in queued again with your current location.';

  @override
  String get proofGeofenceOverride =>
      'Override requested; waiting for the cluster head';

  @override
  String get proofGeofenceOutside => 'Outside the geofence';

  @override
  String get proofPhotoDone => 'Photo with location taken';

  @override
  String get proofDurationDone => 'Minimum duration reached';

  @override
  String get proofIntegrityIssue =>
      'Device checks reported issues; this part scores 0';

  @override
  String get visitConfirmTitle => 'Farmer confirmation';

  @override
  String get visitConfirmIntro =>
      'Ask the farmer to confirm this visit in one of these ways.';

  @override
  String get visitConfirmOtp => 'OTP by SMS';

  @override
  String get visitConfirmOtpHelp =>
      'A code goes to the farmer’s phone; type it here.';

  @override
  String get visitConfirmPush => 'Ask in Kisan app';

  @override
  String get visitConfirmPushHelp => 'The farmer taps Confirm in their app.';

  @override
  String get visitConfirmQr => 'Show QR';

  @override
  String get visitConfirmQrHelp => 'The farmer scans this with the Kisan app.';

  @override
  String get visitConfirmNeedsNetwork =>
      'This needs network. Try again when you are online.';

  @override
  String get visitConfirmQrNeedsSync =>
      'The QR needs one sync first. Connect once and come back.';

  @override
  String get visitConfirmNotSynced =>
      'The check-in has not reached the server yet. Sync and try again.';

  @override
  String get visitConfirmQueued =>
      'Request saved. It goes to the farmer’s app as soon as you are online.';

  @override
  String get visitConfirmWaiting => 'Waiting for the farmer…';

  @override
  String get visitConfirmWaitingPush =>
      'We asked the farmer in the Kisan app. This screen updates when they confirm.';

  @override
  String get visitConfirmQrWaiting => 'Waiting for the farmer to scan…';

  @override
  String get visitConfirmed => 'Farmer confirmed';

  @override
  String visitConfirmedVia(String channel) {
    return 'Confirmed via $channel';
  }

  @override
  String visitConfirmOtpSent(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get visitConfirmAlready => 'This visit is already confirmed.';

  @override
  String get visitConfirmRefused =>
      'The farmer cannot be asked this way right now. Try another option.';

  @override
  String get visitConfirmContinue => 'Continue to check-out';

  @override
  String get visitConfirmLater => 'Confirm later';

  @override
  String visitConfirmExpires(int minutes) {
    return 'Expires in $minutes min';
  }

  @override
  String get visitConfirmChooseAnother => 'Choose another way';

  @override
  String get visitSummaryTitle => 'Check-out summary';

  @override
  String get visitSummaryDuration => 'Duration';

  @override
  String get visitSummaryMissing => 'What was missing';

  @override
  String get visitSummaryComplete => 'Everything is in place';

  @override
  String get visitSummaryPending =>
      'The server confirms the score after the next sync';

  @override
  String get visitSummaryServer => 'Score confirmed by the server';

  @override
  String get visitSummaryNotCheckedOut => 'This visit is still open.';

  @override
  String get visitSummaryOverridePending => 'Override waiting for review';

  @override
  String get visitDone => 'Done';

  @override
  String get syncEntityVisit => 'Visit';

  @override
  String get syncEntityVisitPhoto => 'Visit photo';

  @override
  String get syncEntityVisitConfirmation => 'Farmer confirmation';

  @override
  String get catalogTitle => 'Products';

  @override
  String catalogForFarmer(String name) {
    return 'For $name';
  }

  @override
  String get catalogSearchHint => 'Search name, brand or ingredient';

  @override
  String get catalogCategoryAll => 'All';

  @override
  String get catalogCategorySeed => 'Seeds';

  @override
  String get catalogCategoryFertiliser => 'Fertilisers';

  @override
  String get catalogCategoryPesticide => 'Pesticides';

  @override
  String get catalogCategoryFungicide => 'Fungicides';

  @override
  String get catalogCategoryHerbicide => 'Herbicides';

  @override
  String get catalogCategoryGrowth => 'Growth promoters';

  @override
  String get catalogCategoryTool => 'Tools';

  @override
  String get catalogCategoryOther => 'Other';

  @override
  String catalogAsOf(String time) {
    return 'Prices and stock as of $time';
  }

  @override
  String catalogStale(String time) {
    return 'Prices and stock may be out of date (as of $time). Refresh when online.';
  }

  @override
  String get catalogNeverLoaded => 'The catalogue is not on this phone yet';

  @override
  String get catalogNeverLoadedHelp =>
      'Connect to the internet to download products and prices.';

  @override
  String get catalogRefresh => 'Refresh';

  @override
  String get catalogRefreshFailed =>
      'Could not refresh. Showing saved products.';

  @override
  String get catalogEmpty => 'No products match';

  @override
  String get catalogEmptyHelp => 'Try another name or category.';

  @override
  String get catalogStoreUnknown =>
      'Store not known yet. Stock shows after the next sync.';

  @override
  String get productPriceEstimate => 'Estimated price';

  @override
  String productStockNearest(int count) {
    return '$count in stock at the nearest store';
  }

  @override
  String productStockAsOf(String time) {
    return 'as of $time';
  }

  @override
  String productInCart(int count) {
    return '$count in cart';
  }

  @override
  String get cartEstimatedTotal => 'Estimated total';

  @override
  String get cartViewCart => 'View cart';

  @override
  String get cartTitle => 'Cart';

  @override
  String get cartEmpty => 'The cart is empty';

  @override
  String get cartEmptyHelp => 'Add products from the catalogue.';

  @override
  String get cartAddMore => 'Add more products';

  @override
  String get cartSubtotal => 'Subtotal (estimate)';

  @override
  String get cartTax => 'GST (estimate)';

  @override
  String get cartEstimateNote =>
      'Prices are estimates from the saved price list. The store confirms the final amount when the order syncs.';

  @override
  String get cartFulfilment => 'How will the farmer get it?';

  @override
  String get fulfilmentPickup => 'Pickup at store';

  @override
  String get fulfilmentDelivery => 'Delivery';

  @override
  String get cartChoosePayment => 'Choose payment';

  @override
  String get cartDecrease => 'Remove one';

  @override
  String get cartIncrease => 'Add one';

  @override
  String cartShortLine(String available, String requested) {
    return 'Only $available available at the store (asked $requested).';
  }

  @override
  String cartUseAvailable(String available) {
    return 'Use $available';
  }

  @override
  String get cartShortTitle =>
      'Some items are short at the store. Change the quantities and send again.';

  @override
  String get checkoutTitle => 'Payment';

  @override
  String get checkoutOrderAmount => 'Order total (estimate)';

  @override
  String get checkoutDuesAmount => 'Amount to collect (₹)';

  @override
  String checkoutDuesBalance(String amount) {
    return 'Balance due $amount';
  }

  @override
  String checkoutDuesTooMuch(String amount) {
    return 'Enter an amount up to $amount';
  }

  @override
  String get checkoutDuesInvalid => 'Enter an amount';

  @override
  String get checkoutPlaceOrder => 'Place order';

  @override
  String get checkoutCollect => 'Collect';

  @override
  String get checkoutNeedsInternet => 'Needs internet: use cash or credit';

  @override
  String get checkoutCreditOrdersOnly => 'Credit is only for orders';

  @override
  String checkoutCreditLeft(String amount) {
    return 'Limit left $amount';
  }

  @override
  String get checkoutOfflineNote =>
      'You are offline. Cash and credit are saved on the phone and sent when online.';

  @override
  String get checkoutOrderNotSynced =>
      'The order has not reached the server yet. Try again when online, or collect cash.';

  @override
  String get checkoutNetworkError =>
      'Could not reach the server. Check the internet and try again.';

  @override
  String get checkoutAlreadyPaid => 'This order is already paid.';

  @override
  String get checkoutAmountMismatch =>
      'The amount changed on the server. Check the order and try again.';

  @override
  String get checkoutNothingDue => 'Nothing is due for this farmer.';

  @override
  String checkoutRefused(String code) {
    return 'The payment could not be created ($code).';
  }

  @override
  String get paymentCard => 'Card';

  @override
  String get paymentDone => 'Done';

  @override
  String get upiTitle => 'UPI QR';

  @override
  String get upiExpired => 'QR expired';

  @override
  String get upiCollectCash => 'Collect cash instead';

  @override
  String get linkTitle => 'Payment link';

  @override
  String get linkSentTitle => 'Payment link sent';

  @override
  String linkSentVia(String channel) {
    return 'Sent by $channel. Ask the farmer to open the link and pay.';
  }

  @override
  String get channelSms => 'SMS';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get linkResend => 'Resend the link';

  @override
  String get linkResent => 'Link sent again';

  @override
  String get linkCheckStatus => 'Check payment';

  @override
  String linkValidUntil(String time) {
    return 'Valid until $time';
  }

  @override
  String get cashTitle => 'Cash receipt';

  @override
  String get cashAmount => 'Cash collected';

  @override
  String get cashTakePhoto => 'Take receipt photo';

  @override
  String get cashRetake => 'Retake';

  @override
  String get cashSave => 'Save cash payment';

  @override
  String get cashPhotoHelp =>
      'Photograph the receipt you gave the farmer. Only the in-app camera can be used.';

  @override
  String get cashPhotoBad =>
      'The photo is blurry or dark. Retake it in good light.';

  @override
  String get cashSaved => 'Cash saved. Pending store reconciliation.';

  @override
  String get cashPendingReconciliation =>
      'Pending store reconciliation: the store checks the cash at day close.';

  @override
  String get creditTitle => 'Credit sale';

  @override
  String get creditQueued =>
      'Saved on the phone. The credit limit is checked when the phone is online.';

  @override
  String get creditApprovedTitle => 'Added to the farmer’s khata';

  @override
  String get creditNeedsApprovalTitle => 'Approval needed';

  @override
  String get creditNeedsApprovalBody =>
      'This sale is over the farmer’s credit limit. It was sent to the cluster head for approval.';

  @override
  String get creditLimit => 'Credit limit';

  @override
  String get creditBalance => 'Balance due now';

  @override
  String get creditShortfall => 'Over the limit by';

  @override
  String get creditSentToClusterHead => 'Sent to cluster head';

  @override
  String get creditCheckAgain => 'Check approval';

  @override
  String get creditStillPending => 'Not approved yet. Try again later.';

  @override
  String get creditOfflineCheck =>
      'Connect to the internet to check the approval.';

  @override
  String get creditUseCash => 'Collect cash instead';

  @override
  String get orderTitle => 'Order';

  @override
  String get orderPlacedTitle => 'Order placed';

  @override
  String get orderQueuedTitle => 'Order saved, waiting to sync';

  @override
  String get orderQueuedHelp =>
      'It goes to the store as soon as the phone is online.';

  @override
  String get orderRejectedTitle => 'The store could not take this order';

  @override
  String get orderInsufficientStock => 'Some items are short at the store:';

  @override
  String orderShortLine(String product, String available, String requested) {
    return '$product: $available available, $requested asked';
  }

  @override
  String get orderSkuNotRecommendable =>
      'A product is not approved for this crop and pest (label claim). Remove it and send again.';

  @override
  String get orderEditAndResend => 'Edit and send again';

  @override
  String get orderSummary => 'Summary';

  @override
  String get orderSubtotal => 'Subtotal';

  @override
  String get orderTax => 'GST';

  @override
  String get orderTotal => 'Total';

  @override
  String get orderTotalEstimate => 'Total (estimate)';

  @override
  String get orderStatusTitle => 'Status';

  @override
  String get orderStatusPlaced => 'Placed';

  @override
  String get orderStatusReserved => 'Stock reserved';

  @override
  String get orderStatusPacked => 'Packed';

  @override
  String get orderStatusReady => 'Ready';

  @override
  String get orderStatusHandedOver => 'Handed over';

  @override
  String get orderStatusDelivered => 'Delivered';

  @override
  String get orderStatusCancelled => 'Cancelled';

  @override
  String get orderPayments => 'Payments';

  @override
  String get orderNoPayments => 'No payment yet';

  @override
  String get orderShareInvoice => 'Share invoice on WhatsApp';

  @override
  String get orderShareOffline =>
      'Connect to the internet to share the invoice.';

  @override
  String get orderShareNoInvoice =>
      'The invoice is issued when the store hands over the order.';

  @override
  String get orderShareFailed => 'Could not get the invoice link. Try again.';

  @override
  String orderShareText(String number, String url) {
    return 'Invoice $number: $url';
  }

  @override
  String orderInvoiceNo(String number) {
    return 'Invoice $number';
  }

  @override
  String get orderCollectPayment => 'Collect payment';

  @override
  String get orderPendingSync => 'Waiting to sync';

  @override
  String get orderRejected => 'Needs attention';

  @override
  String get ordersTitle => 'Orders';

  @override
  String get ordersEmpty => 'No orders yet';

  @override
  String get ordersEmptyHelp => 'Orders you place for farmers show here.';

  @override
  String get ordersNew => 'New order';

  @override
  String get ordersCollections => 'Collections';

  @override
  String get ordersPickFarmer => 'Choose a farmer';

  @override
  String get khataTitle => 'Khata';

  @override
  String khataAsOf(String time) {
    return 'As of $time';
  }

  @override
  String khataOfflineAsOf(String time) {
    return 'Offline: showing the khata saved at $time';
  }

  @override
  String get khataNotLoaded => 'Khata not on this phone yet';

  @override
  String get khataNotLoadedHelp =>
      'Connect to the internet to load the farmer’s khata.';

  @override
  String khataOverdue(String amount) {
    return 'Overdue $amount';
  }

  @override
  String get khataBucket0to30 => '0–30 days';

  @override
  String get khataBucket31to60 => '31–60 days';

  @override
  String get khataBucket61to90 => '61–90 days';

  @override
  String get khataBucket90plus => '90+ days';

  @override
  String khataDueHarvest(String date, String month) {
    return 'Due $date · harvest $month';
  }

  @override
  String get khataEntryOrder => 'Sale on credit';

  @override
  String get khataEntryPayment => 'Payment received';

  @override
  String get khataEntryAdjustment => 'Adjustment';

  @override
  String get khataPaymentHistory => 'Payment history';

  @override
  String get khataNoPayments => 'No payments yet';

  @override
  String get khataPendingCollections => 'Collected, not yet on the khata';

  @override
  String get collectionsTitle => 'Collections';

  @override
  String get collectionsToday => 'Today';

  @override
  String get collectionsWeek => 'This week';

  @override
  String get collectionsTotal => 'Collected';

  @override
  String get collectionsEmpty => 'No collections yet';

  @override
  String get collectionsEmptyHelp => 'Payments you collect show here.';

  @override
  String get collectionStateWaitingToSync => 'Waiting to sync';

  @override
  String get collectionStatePendingReconciliation => 'Pending reconciliation';

  @override
  String get collectionStateWaiting => 'Waiting for payment';

  @override
  String get collectionStatePaid => 'Paid';

  @override
  String get collectionStateOnKhata => 'On khata';

  @override
  String get collectionStateApprovalNeeded => 'Approval needed';

  @override
  String get collectionStateFailed => 'Failed';

  @override
  String get syncEntityOrder => 'Order';

  @override
  String get syncEntityPayment => 'Payment';

  @override
  String get storeModeTitle => 'Store mode';

  @override
  String get storeSettingsEntryHint => 'Sales, orders, stock and day close';

  @override
  String get storeNavHome => 'Home';

  @override
  String get storeNavPos => 'Sell';

  @override
  String get storeNavQueue => 'Orders';

  @override
  String get storeNavStock => 'Stock';

  @override
  String get storeNavCredit => 'Credit';

  @override
  String get storeNavDayClose => 'Day close';

  @override
  String get storeReadOnlyBanner =>
      'You are viewing this store. Only the store team can make changes.';

  @override
  String get storeNotAllowedTitle => 'Store mode is not available';

  @override
  String get storeNotAllowedHelp =>
      'Store mode is for store managers, accountants and cluster heads.';

  @override
  String get storeOfflineTitle => 'You are offline';

  @override
  String get storeOfflineHelp =>
      'Store mode needs the network. Check the connection and try again.';

  @override
  String get storeErrorTitle => 'Could not load';

  @override
  String get storeErrorHelp => 'Something went wrong. Try again.';

  @override
  String get storeSwitchStore => 'Switch store';

  @override
  String get storeHomeTitle => 'Store home';

  @override
  String get storeTodaySales => 'Today\'s sales';

  @override
  String storeSalesCount(int count) {
    return 'Payments: $count';
  }

  @override
  String get storeModeUpi => 'UPI QR';

  @override
  String get storeModeCard => 'Card';

  @override
  String get storeModeCash => 'Cash';

  @override
  String get storeModeCredit => 'Credit (khata)';

  @override
  String get storeQueueCounts => 'Order queue';

  @override
  String get storeTabNew => 'New';

  @override
  String get storeTabPacking => 'Packing';

  @override
  String get storeTabReady => 'Ready';

  @override
  String get storeTabHandedOver => 'Handed over';

  @override
  String storeTabWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get storeLowStock => 'Low stock';

  @override
  String storeLowStockCount(int count) {
    return 'Items low: $count';
  }

  @override
  String storeExpiringCount(int count) {
    return 'Expiring soon: $count';
  }

  @override
  String get storeDayCloseStatus => 'Day close';

  @override
  String get storeDayOpen => 'Open, not closed yet';

  @override
  String storeDayClosed(String time) {
    return 'Closed at $time';
  }

  @override
  String get storeDayReopened => 'Reopened';

  @override
  String get storeActionNewSale => 'New sale';

  @override
  String get storeActionReceive => 'Goods receipt';

  @override
  String get storeActionTransfer => 'Stock transfer';

  @override
  String get storeActionCloseDay => 'Close day';

  @override
  String get storePosTitle => 'Point of sale';

  @override
  String get storeSearchProducts => 'Search products';

  @override
  String get storeScan => 'Scan';

  @override
  String get storeEnterCode => 'Enter code';

  @override
  String get storeCodeHint => 'Barcode number';

  @override
  String get storeCodeAdd => 'Add';

  @override
  String storeScanAdded(String name) {
    return '$name added';
  }

  @override
  String storeScanNotFound(String code) {
    return 'No product with code $code';
  }

  @override
  String get storeScanOffline => 'Offline: the code cannot be looked up';

  @override
  String get storeCategoryAll => 'All';

  @override
  String get storeCategorySeed => 'Seeds';

  @override
  String get storeCategoryFertiliser => 'Fertilisers';

  @override
  String get storeCategoryPesticide => 'Insecticides';

  @override
  String get storeCategoryFungicide => 'Fungicides';

  @override
  String get storeCategoryHerbicide => 'Herbicides';

  @override
  String get storeCategoryGrowth => 'Growth promoters';

  @override
  String get storeCategoryTool => 'Tools';

  @override
  String get storeCategoryOther => 'Other';

  @override
  String get storeCartTitle => 'Cart';

  @override
  String get storeCartEmpty => 'Cart is empty';

  @override
  String get storeCartEmptyHelp => 'Scan a barcode or tap a product to add it.';

  @override
  String get storeQtyDecrease => 'Decrease';

  @override
  String get storeQtyIncrease => 'Increase';

  @override
  String get storeSubtotal => 'Subtotal (before GST)';

  @override
  String get storeGst => 'GST';

  @override
  String get storeTotal => 'Total';

  @override
  String get storeRoundOff => 'Round off';

  @override
  String get storeBuyerPhone => 'Farmer phone';

  @override
  String get storeBuyerFind => 'Find';

  @override
  String get storeBuyerWalkIn => 'Leave empty for a walk-in customer';

  @override
  String get storeBuyerUnknown =>
      'New number: the sale is recorded against this phone';

  @override
  String get storeBuyerClear => 'Remove';

  @override
  String get storeNoProducts => 'No products match';

  @override
  String get storeCheckoutTitle => 'Checkout';

  @override
  String get storePayWith => 'Payment method';

  @override
  String get storeModeUpiHint => 'Farmer scans the QR';

  @override
  String get storeModeCardHint => 'Card on the store terminal';

  @override
  String get storeModeCashHint => 'Count the cash, give change';

  @override
  String get storeModeCreditHint => 'Add to the farmer\'s khata';

  @override
  String get storeCardReference => 'Terminal reference';

  @override
  String get storeCardReferenceHint => 'Approval code on the slip';

  @override
  String get storeCardReferenceRequired => 'Enter the terminal reference';

  @override
  String get storeCashTendered => 'Cash received';

  @override
  String get storeCashChange => 'Change to give';

  @override
  String get storeCashShort => 'Cash received is less than the total';

  @override
  String get storeCreditNeedsFarmer =>
      'Credit needs a registered farmer. Find the farmer by phone.';

  @override
  String get storeInvoicePreview => 'GST invoice preview';

  @override
  String get storeInvoicePreviewNote =>
      'The invoice number and final tax come from the server when you confirm.';

  @override
  String get storeColItem => 'Item';

  @override
  String get storeColHsn => 'HSN';

  @override
  String get storeColQty => 'Qty';

  @override
  String get storeColRate => 'Rate';

  @override
  String get storeColGst => 'GST';

  @override
  String get storeColAmount => 'Amount';

  @override
  String get storeTaxable => 'Taxable value';

  @override
  String get storeCgst => 'CGST';

  @override
  String get storeSgst => 'SGST';

  @override
  String get storeIgst => 'IGST';

  @override
  String get storeConfirmSale => 'Confirm sale';

  @override
  String get storeOfflineSaleTitle => 'Offline: the sale cannot be completed';

  @override
  String get storeOfflineSaleHelp =>
      'The cart is kept. Connect to the network and confirm again.';

  @override
  String get storeApprovalNeededTitle => 'Credit approval needed';

  @override
  String storeApprovalNeededHelp(String amount) {
    return 'This sale is $amount over the farmer\'s limit. A cluster head must approve it. The cart is kept.';
  }

  @override
  String get storeCreditBalance => 'Khata balance';

  @override
  String get storeCreditLimit => 'Credit limit';

  @override
  String get storeChooseAnotherMode => 'Choose another method';

  @override
  String get storeSaleFailedTitle => 'Sale not completed';

  @override
  String storeSaleFailed(String code) {
    return 'The server refused the sale ($code). The cart is kept.';
  }

  @override
  String get storeInvoiceTitle => 'Tax invoice';

  @override
  String storeInvoiceNo(String number) {
    return 'Invoice $number';
  }

  @override
  String get storeInvoicePaid => 'Sale complete';

  @override
  String get storeInvoiceBuyer => 'Billed to';

  @override
  String storeGstin(String gstin) {
    return 'GSTIN $gstin';
  }

  @override
  String get storeAmountInWords => 'Amount in words';

  @override
  String get storeOpenPdf => 'Open PDF';

  @override
  String get storeShareWhatsApp => 'Send on WhatsApp';

  @override
  String get storeShareOther => 'Share';

  @override
  String storeShareSent(String to) {
    return 'Sent to $to';
  }

  @override
  String get storeShareFailed => 'Could not send. Try again.';

  @override
  String get storePdfFailed => 'Could not open the PDF.';

  @override
  String storeShareText(String number, String amount, String url) {
    return 'Invoice $number for $amount: $url';
  }

  @override
  String get storeNextSale => 'Next sale';

  @override
  String get storeQueueTitle => 'Order queue';

  @override
  String storeOrderRef(String ref) {
    return 'Order #$ref';
  }

  @override
  String get storeChannelOfficer => 'Field officer';

  @override
  String get storeChannelFarmerApp => 'Farmer app';

  @override
  String get storeChannelPos => 'Counter';

  @override
  String get storeFulfilmentPickup => 'Pick-up';

  @override
  String get storeFulfilmentDelivery => 'Delivery';

  @override
  String get storeStatusPlaced => 'Placed';

  @override
  String get storeStatusReserved => 'Stock reserved';

  @override
  String get storeStatusPacked => 'Packed';

  @override
  String get storeStatusReady => 'Ready';

  @override
  String get storeStatusHandedOver => 'Handed over';

  @override
  String get storeStatusDelivered => 'Delivered';

  @override
  String get storeStatusCancelled => 'Cancelled';

  @override
  String get storeActionReserve => 'Reserve stock';

  @override
  String get storeActionPack => 'Mark packed';

  @override
  String get storeActionReady => 'Mark ready';

  @override
  String get storeActionHandOver => 'Hand over';

  @override
  String get storeActionDeliver => 'Mark delivered';

  @override
  String get storeActionCancel => 'Cancel order';

  @override
  String get storeCancelReason => 'Reason for cancelling';

  @override
  String get storeKeepOrder => 'Keep order';

  @override
  String get storeTransitionFailed =>
      'This change is not allowed now. The list was refreshed.';

  @override
  String get storeQueueEmpty => 'No orders here';

  @override
  String get storeQueueEmptyHelp =>
      'Orders from field officers and the farmer app appear here.';

  @override
  String get storeSelectOrder => 'Select an order to see its details';

  @override
  String storeFarmerUnknown(String ref) {
    return 'Farmer $ref';
  }

  @override
  String storeOrderMoved(String status) {
    return 'Order is now: $status';
  }

  @override
  String get storeStockTitle => 'Stock';

  @override
  String get storeOnHand => 'On hand';

  @override
  String get storeReserved => 'Reserved';

  @override
  String get storeAvailable => 'Available';

  @override
  String storeBatch(String number) {
    return 'Batch $number';
  }

  @override
  String storeExpires(String date) {
    return 'Expires $date';
  }

  @override
  String get storeNoExpiry => 'No expiry';

  @override
  String get storeExpired => 'Expired';

  @override
  String get storeExpiring30 => 'Expires within 30 days';

  @override
  String get storeExpiring60 => 'Expires within 60 days';

  @override
  String get storeFilterLow => 'Low stock';

  @override
  String get storeFilterExpiring => 'Expiring';

  @override
  String get storeStockEmpty => 'No stock matches';

  @override
  String get storeStockEmptyHelp => 'Change the filters or receive goods.';

  @override
  String get storeSelectSku => 'Select an item to see its batches';

  @override
  String get storeWriteOff => 'Write off';

  @override
  String get storeWriteOffTitle => 'Write off stock';

  @override
  String get storeAdjust => 'Adjust count';

  @override
  String get storeAdjustTitle => 'Adjust to the counted stock';

  @override
  String get storeCountedQty => 'Counted quantity';

  @override
  String get storeAdjustReasonHint => 'Why the count differs';

  @override
  String get storeReason => 'Reason';

  @override
  String get storeReasonRequired => 'Enter a reason';

  @override
  String get storeReasonDamage => 'Damaged';

  @override
  String get storeReasonExpiry => 'Expired';

  @override
  String get storeReasonOther => 'Other';

  @override
  String get storeQuantity => 'Quantity';

  @override
  String get storeQtyRequired => 'Enter a quantity above zero';

  @override
  String storeQtyTooHigh(String qty) {
    return 'More than available ($qty)';
  }

  @override
  String storeAvailableQty(String qty) {
    return 'Available: $qty';
  }

  @override
  String get storeAddPhoto => 'Add photo';

  @override
  String get storePhotoAdded => 'Photo added';

  @override
  String get storeNote => 'Note';

  @override
  String get storeSubmit => 'Save';

  @override
  String get storeSaved => 'Saved';

  @override
  String get storeNegativeStock => 'Not enough unreserved stock';

  @override
  String get storeReceiptTitle => 'Goods receipt';

  @override
  String get storeReference => 'Supplier invoice / reference';

  @override
  String get storeSku => 'Item';

  @override
  String get storeFindSku => 'Item (pick or scan)';

  @override
  String get storeSkuRequired => 'Choose an item';

  @override
  String get storeBatchNo => 'Batch number';

  @override
  String get storeBatchNoRequired => 'Enter the batch number';

  @override
  String get storeExpiryDate => 'Expiry date';

  @override
  String get storeExpiryPast => 'The expiry date has passed';

  @override
  String get storeUnitCost => 'Unit cost (₹)';

  @override
  String get storeCostRequired => 'Enter the cost';

  @override
  String get storeAddLine => 'Add line';

  @override
  String get storeRemoveLine => 'Remove line';

  @override
  String get storeReceiptSubmit => 'Receive stock';

  @override
  String get storeReceiptDone => 'Stock received';

  @override
  String storeReceiptDoneHelp(int lines, String qty) {
    return 'Lines: $lines · units added: $qty';
  }

  @override
  String get storeBatchMismatch =>
      'This batch already exists with another expiry date';

  @override
  String get storeTransferTitle => 'Stock transfer';

  @override
  String get storeToStore => 'To store';

  @override
  String get storeToStoreRequired => 'Choose the destination store';

  @override
  String get storeNoOtherStores =>
      'No other store is available to you. Ask your cluster head.';

  @override
  String get storeChooseBatch => 'Batch';

  @override
  String get storeFefoSuggested => 'Earliest expiry first (suggested)';

  @override
  String get storeTransferSubmit => 'Transfer';

  @override
  String get storeTransferDone => 'Transfer done';

  @override
  String get storeCreditTitle => 'Credit';

  @override
  String get storeApprovalsEmpty => 'No pending approvals';

  @override
  String get storeApprovalAmount => 'Sale amount';

  @override
  String get storeShortfall => 'Over the limit by';

  @override
  String get storeApprove => 'Approve';

  @override
  String get storeReject => 'Reject';

  @override
  String get storeDecisionNote => 'Note (optional)';

  @override
  String get storeApproved => 'Approved. The store can complete the sale once.';

  @override
  String get storeRejected => 'Rejected';

  @override
  String get storeApprovalGone => 'This request was already decided';

  @override
  String get storeSetLimitTitle => 'Set a farmer\'s credit limit';

  @override
  String get storeLimitAmount => 'Limit (₹)';

  @override
  String get storeLimitAmountRequired => 'Enter the limit in rupees';

  @override
  String get storeSetLimit => 'Save limit';

  @override
  String storeLimitSaved(String amount) {
    return 'Limit saved: $amount';
  }

  @override
  String storeLimitNeedsClusterHead(String cap) {
    return 'Limits above $cap need a cluster head. Ask your cluster head to set this limit.';
  }

  @override
  String get storeLimitFarmerNotFound =>
      'No farmer with this phone on this tablet';

  @override
  String storeManagerCapHint(String cap) {
    return 'You can set up to $cap';
  }

  @override
  String get storeDayCloseTitle => 'Day close';

  @override
  String get storeCashCount => 'Cash count';

  @override
  String get storeCoins => 'Coins (₹)';

  @override
  String get storeExpectedCash => 'Expected cash';

  @override
  String get storeCountedCash => 'Counted cash';

  @override
  String get storeVariance => 'Variance';

  @override
  String storeVarianceOver(String threshold) {
    return 'Variance is over $threshold: auditors will be notified';
  }

  @override
  String get storeDepositSlip => 'Bank deposit slip photo';

  @override
  String get storeTakePhoto => 'Take photo';

  @override
  String get storeRetakePhoto => 'Retake photo';

  @override
  String get storeSlipRequired => 'Take a photo of the deposit slip';

  @override
  String get storeCloseNotes => 'Notes';

  @override
  String get storeCloseDay => 'Close day';

  @override
  String get storeDayClosedTitle => 'Day closed';

  @override
  String get storeDayAlreadyClosed =>
      'Today is already closed. A cluster head can reopen it.';

  @override
  String get storeFlagged => 'Flagged for audit';

  @override
  String get storePreviewEstimate => 'Estimate';

  @override
  String get storePreviewLoading => 'Updating the preview…';

  @override
  String get storePreviewServerNote =>
      'Priced by the server, as the invoice will be. The invoice number is taken when you confirm.';

  @override
  String get storePreviewOffline =>
      'Preview unavailable offline. The amounts are an estimate; the server prices the invoice when you confirm.';

  @override
  String get storePreviewUnavailable =>
      'Preview unavailable. The amounts are an estimate; the server prices the invoice when you confirm.';

  @override
  String get storeCheckApproval => 'Check approval';

  @override
  String get storeApprovalPending =>
      'Not approved yet. The cart is kept; check again later.';

  @override
  String get storeApprovalRejected =>
      'The cluster head rejected this credit sale. Choose another method.';

  @override
  String get storeApprovalCheckOffline =>
      'Could not check the approval. Connect to the internet and try again.';

  @override
  String get storeTransferSourceNotAllowed =>
      'You can send stock only from your own store.';

  @override
  String get storeTransferDestinationNotAllowed =>
      'You cannot send stock to that store. Pick a store from the list.';

  @override
  String storeDistanceKm(String km) {
    return '$km km away';
  }

  @override
  String get creditApprovedSending =>
      'Approved by the cluster head. Sending the sale…';

  @override
  String get creditRejectedByClusterHead =>
      'The cluster head rejected this credit sale. Collect cash instead.';

  @override
  String get loginDeviceNotBound =>
      'This phone is not registered to you. Ask your administrator to approve it, then sign in again.';

  @override
  String get wipeTitle => 'Signed out by your administrator';

  @override
  String get wipeBody =>
      'Your administrator signed this phone out of the app. For safety, the app data on this phone has been deleted.';

  @override
  String get wipeDeletedList =>
      'Deleted: saved farmers, visits, orders, photos and any work that was not yet sent. Your language setting is kept.';

  @override
  String get wipeWhatNext =>
      'If this is a mistake, contact your administrator. Once they allow it, you can sign in again.';

  @override
  String get wipeSignInAgain => 'Sign in again';

  @override
  String get audioListen => 'Listen';

  @override
  String get audioUnavailable => 'Audio unavailable';

  @override
  String get kisanLanguagePrompt => 'You chose English. Tap Continue.';

  @override
  String get kisanAbout => 'About';

  @override
  String kisanAboutVersion(String app, String version) {
    return '$app version $version';
  }

  @override
  String kisanAcres(String count) {
    return '$count acres';
  }

  @override
  String kisanAcresPlus(String count) {
    return '$count+ acres';
  }

  @override
  String get kisanAddToCart => 'Add to cart';

  @override
  String kisanAsOf(String time) {
    return 'Updated $time';
  }

  @override
  String kisanOfflineAsOf(String time) {
    return 'Offline. Saved on $time';
  }

  @override
  String kisanBalanceNow(String amount) {
    return 'Balance now: $amount';
  }

  @override
  String get kisanBuyProducts => 'Buy products';

  @override
  String get kisanCall => 'Call';

  @override
  String get kisanCartEmpty => 'Your cart is empty';

  @override
  String get kisanCartTitle => 'My cart';

  @override
  String get kisanCheckMyCrop => 'Check my crop';

  @override
  String get kisanConfirmWithoutRating => 'Confirm without rating';

  @override
  String get kisanConsentAgree => 'I agree';

  @override
  String get kisanConsentDataHowToStop =>
      'This is needed to use Kisan. To stop it, delete your account.';

  @override
  String get kisanConsentDataNeeded =>
      'Say yes to the first card to use Kisan.';

  @override
  String get kisanConsentDataNotice =>
      'We keep your name, phone, village, farm and crop photos to give you advice. Your field officer and store can see them. We never sell your data.';

  @override
  String kisanConsentGivenOn(String date) {
    return 'Given on $date';
  }

  @override
  String get kisanConsentIntro =>
      'Please read or listen. You can change the second choice any time in Me.';

  @override
  String get kisanConsentOffersNotice =>
      'We send offers and farming tips by SMS or WhatsApp. You can stop them any time in Me.';

  @override
  String get kisanConsentPending =>
      'Saved on this phone. Will send when online.';

  @override
  String get kisanConsentSettings => 'My consent';

  @override
  String get kisanConsentTitle => 'Before we start';

  @override
  String kisanConsentWithdrawnOn(String date) {
    return 'Stopped on $date';
  }

  @override
  String get kisanCouldNotOpen => 'Could not open. Try again.';

  @override
  String get kisanCreditStoreWillConfirm => 'Your store will confirm';

  @override
  String get kisanCropDoctorSoonHelp =>
      'Soon you can take a photo of your crop here and get advice.';

  @override
  String get kisanCropDoctorSoonTitle => 'Crop doctor is coming';

  @override
  String get kisanCropUnknown => 'Crop';

  @override
  String get kisanDeleteAccount => 'Delete my account';

  @override
  String get kisanDeleteAfter =>
      'You can keep using Kisan until then. Call your store if you change your mind.';

  @override
  String get kisanDeleteAreYouSure =>
      'Are you sure? Your account and data will be deleted. This cannot be undone.';

  @override
  String kisanDeleteDueBy(String date) {
    return 'We will finish by $date';
  }

  @override
  String get kisanDeleteExplain =>
      'We will delete your account, your farm details, crop photos and messages. Records the law asks us to keep, like bills, are kept and then deleted.';

  @override
  String get kisanDeleteKeep => 'No, keep my account';

  @override
  String get kisanDeleteKeepsDues =>
      'Money you owe the store is still due after the account is deleted.';

  @override
  String kisanDeleteRequested(String ticket) {
    return 'Request sent · $ticket';
  }

  @override
  String get kisanDeleteStatusCompleted => 'Your account has been deleted';

  @override
  String get kisanDeleteStatusInProgress => 'We are deleting your data';

  @override
  String get kisanDeleteStatusReceived => 'We got your request';

  @override
  String kisanDeleteTicket(String ticket) {
    return 'Ticket $ticket';
  }

  @override
  String get kisanDeleteYes => 'Yes, delete';

  @override
  String get kisanDelivery => 'Home delivery';

  @override
  String kisanDuesTitle(String amount) {
    return 'You owe $amount';
  }

  @override
  String get kisanFarmUnnamed => 'My farm';

  @override
  String get kisanFieldOfficer => 'Field officer';

  @override
  String get kisanGoToPay => 'Go to pay';

  @override
  String kisanGreeting(String name) {
    return 'Namaste, $name';
  }

  @override
  String get kisanGreetingNoName => 'Namaste';

  @override
  String get kisanHelpCallStore => 'Help: call the store';

  @override
  String get kisanHelpNoPhone => 'Store phone not set yet';

  @override
  String get kisanHowMany => 'How many?';

  @override
  String get kisanHowPay => 'How will you pay?';

  @override
  String kisanInStock(String count) {
    return '$count in stock at your store';
  }

  @override
  String get kisanIrrigationQuestion => 'How do you water the farm?';

  @override
  String get kisanIrrigationUnknown => 'Water: not set';

  @override
  String get kisanItems => 'Items';

  @override
  String get kisanKhataNotLoaded => 'Khata not on this phone yet';

  @override
  String get kisanLess => 'Less';

  @override
  String get kisanMore => 'More';

  @override
  String get kisanMyCrops => 'My crops';

  @override
  String get kisanMyOfficer => 'My field officer';

  @override
  String get kisanMyOrders => 'My orders';

  @override
  String get kisanNavCropDoctor => 'Crop doctor';

  @override
  String get kisanNavHome => 'Home';

  @override
  String get kisanNavMe => 'Me';

  @override
  String get kisanNavOrders => 'Orders';

  @override
  String get kisanNeedsInternet =>
      'This needs internet. Try again when online.';

  @override
  String get kisanNextTaskSoon => 'Next task: coming soon';

  @override
  String get kisanNo => 'No';

  @override
  String get kisanNoAlerts => 'No pest alerts in your area';

  @override
  String get kisanNoCropsHelp =>
      'Your field officer or store can add your farm.';

  @override
  String get kisanNoCropsYet => 'No crops yet';

  @override
  String get kisanNotifications => 'Notifications';

  @override
  String get kisanNotPaidYet =>
      'Not paid yet. You can pay later or at the store.';

  @override
  String get kisanOff => 'Off';

  @override
  String get kisanOffersOff => 'Offers and tips: off';

  @override
  String get kisanOffersOn => 'Offers and tips: on';

  @override
  String get kisanOfficerPhoneMissing =>
      'The officer’s phone is not in the app yet. Ask at your store.';

  @override
  String get kisanOn => 'On';

  @override
  String get kisanOrderCollected => 'Collected';

  @override
  String get kisanOrderNotSaved => 'This order is not on this phone yet';

  @override
  String get kisanOrderOnKhata => 'On your khata';

  @override
  String get kisanOrderPaid => 'Paid';

  @override
  String get kisanOrderPlaced => 'Order placed';

  @override
  String get kisanOrdersEmptyHelp =>
      'Tap Buy products to order from your store.';

  @override
  String get kisanOrderShort =>
      'The store does not have enough of an item. Change the amount.';

  @override
  String get kisanOrderTitle => 'My order';

  @override
  String get kisanOutOfStock => 'Not in stock now';

  @override
  String kisanPaidOn(String time) {
    return 'Paid on $time';
  }

  @override
  String get kisanPaidThanks => 'Paid. Thank you!';

  @override
  String get kisanPayAtStore => 'Pay at store';

  @override
  String get kisanPayAtStoreHelp => 'Pay cash or UPI when you collect';

  @override
  String get kisanPayAtStoreNote => 'Pay at the store when you collect';

  @override
  String get kisanPayCredit => 'Ask for credit';

  @override
  String get kisanPaymentDone => 'Payment received';

  @override
  String get kisanPaymentFailed =>
      'The payment did not go through. No money was taken.';

  @override
  String kisanPaymentRef(String ref) {
    return 'Reference: $ref';
  }

  @override
  String get kisanPayTitle => 'Pay';

  @override
  String get kisanPayUpi => 'Pay by UPI';

  @override
  String get kisanPayUpiHelp => 'Opens PhonePe, Google Pay or your UPI app';

  @override
  String get kisanPickup => 'Pick up at store';

  @override
  String get kisanPickupQuestion => 'How will you get it?';

  @override
  String kisanPlacedOn(String time) {
    return 'Ordered on $time';
  }

  @override
  String get kisanPlaceOrder => 'Place order';

  @override
  String get kisanProductTitle => 'Product';

  @override
  String get kisanRateQuestion => 'How was the visit?';

  @override
  String get kisanRateTitle => 'Rate the visit';

  @override
  String get kisanRateWhy => 'Why?';

  @override
  String get kisanReasonAdviceUnclear => 'Advice not clear';

  @override
  String get kisanReasonDidNotSeeCrop => 'Did not see my crop';

  @override
  String get kisanReasonLookedAtCrop => 'Looked at my crop';

  @override
  String get kisanReasonOnTime => 'Came on time';

  @override
  String get kisanReasonTooShort => 'Visit too short';

  @override
  String get kisanReasonUsefulAdvice => 'Useful advice';

  @override
  String get kisanReceiptTitle => 'Receipt';

  @override
  String get kisanSave => 'Save';

  @override
  String get kisanSaved => 'Saved';

  @override
  String get kisanSavedWillSend =>
      'Saved. We will send it when you are online.';

  @override
  String get kisanSaveFailed => 'Could not save. Try again.';

  @override
  String get kisanScanButton => 'Scan QR';

  @override
  String get kisanScanHelp =>
      'Ask your field officer to show the QR on their phone, then scan it.';

  @override
  String get kisanScanNotVisitQr =>
      'This is not a visit QR. Scan the QR on your officer’s phone.';

  @override
  String get kisanScanTitle => 'Scan the visit QR';

  @override
  String get kisanScanVisitQr => 'Scan visit QR';

  @override
  String get kisanSend => 'Send';

  @override
  String get kisanSetupCropQuestion => 'Which crop do you grow?';

  @override
  String get kisanSetupLandQuestion => 'How much land?';

  @override
  String get kisanSetupNoVillages =>
      'Village list not on this phone yet. Your store will add it.';

  @override
  String get kisanSetupSownQuestion => 'When did you sow?';

  @override
  String get kisanSetupVillageQuestion => 'Your village';

  @override
  String get kisanShopEmptyHelp => 'Try another group of products.';

  @override
  String get kisanShopHelp =>
      'Tap a product to see it and add it to your cart.';

  @override
  String get kisanSkipForNow => 'Skip for now';

  @override
  String get kisanSoilQuestion => 'What is your soil?';

  @override
  String get kisanSoilUnknown => 'Soil: not set';

  @override
  String get kisanSownLonger => '3 months or more';

  @override
  String get kisanSownThisMonth => 'This month';

  @override
  String get kisanSownThisWeek => 'This week';

  @override
  String get kisanSownTwoMonths => '1–2 months ago';

  @override
  String kisanStageIs(String stage) {
    return 'Stage: $stage';
  }

  @override
  String get kisanStageQuestion => 'What stage is the crop in?';

  @override
  String get kisanStageUnknown => 'Stage: not set';

  @override
  String get kisanTotalEstimateNote => 'The store confirms the final price.';

  @override
  String kisanTotalToPay(String amount) {
    return 'Total $amount';
  }

  @override
  String get kisanUpiNoApp =>
      'No UPI app opened. Install a UPI app or pay at the store.';

  @override
  String get kisanUpiOpenAgain => 'Open UPI app again';

  @override
  String get kisanUpiWaiting => 'Finish the payment in your UPI app';

  @override
  String get kisanViewCart => 'View cart';

  @override
  String get kisanVisitAlreadyAnswered =>
      'You already answered for this visit.';

  @override
  String get kisanVisitNoThanks => 'Thank you. We will check with the officer.';

  @override
  String kisanVisitQuestion(String name) {
    return 'Did $name visit your farm today?';
  }

  @override
  String get kisanVisitQuestionNoName =>
      'Did your field officer visit your farm today?';

  @override
  String get kisanVisitTapToAnswer => 'Tap to answer';

  @override
  String get kisanVisitThanks => 'Thank you! The visit is confirmed.';

  @override
  String get kisanVisitTitle => 'Field officer visit';

  @override
  String get kisanVisitTokenInvalid =>
      'This question has expired. Ask your officer to show the QR.';

  @override
  String get kisanWeatherSoon => 'Weather for your farm is coming soon';

  @override
  String get kisanWelcomeChange => 'Something is wrong: change';

  @override
  String get kisanWelcomeConfirmHelp => 'Please check your farm and crops.';

  @override
  String get kisanWelcomeCorrect => 'Yes, this is right';

  @override
  String get kisanWelcomeEditHelp => 'Tap a picture to change it.';

  @override
  String kisanWelcomeFromOfficer(String name) {
    return 'Your farm details from $name (field officer)';
  }

  @override
  String get kisanWelcomeFromYourOfficer =>
      'Your farm details from your field officer';

  @override
  String get kisanWelcomeTitle => 'Welcome';

  @override
  String get kisanWhatsApp => 'WhatsApp';

  @override
  String get kisanYes => 'Yes';

  @override
  String get kisanYourOfficer => 'Your field officer';

  @override
  String get photoTipNotPlant =>
      'Point the camera at the sick leaf and take it again';

  @override
  String get photoQualityNotPlant => 'No leaf seen';

  @override
  String get treatmentPpeClothing => 'Full sleeves';

  @override
  String get cropDoctorTitle => 'Crop doctor';

  @override
  String get cropDoctorIntroTitle => 'Take a photo of the sick leaf';

  @override
  String get cropDoctorIntroTip1 => 'Go close to one sick leaf';

  @override
  String get cropDoctorIntroTip2 => 'Stand with the sun behind you';

  @override
  String get cropDoctorIntroTip3 => 'Hold still and tap the leaf to focus';

  @override
  String get cropDoctorUpTo3 => 'You can take up to 3 photos';

  @override
  String get cropDoctorOpenCamera => 'Open camera';

  @override
  String get cropDoctorTakePhoto => 'Take photo';

  @override
  String get cropDoctorCameraDenied =>
      'Allow the camera to take a photo of your crop';

  @override
  String get cropDoctorCameraError => 'The camera did not open. Try again.';

  @override
  String get cropDoctorTryAgain => 'Try again';

  @override
  String cropDoctorPhotoCount(int count) {
    return 'Photo $count of 3';
  }

  @override
  String cropDoctorPhotosReady(int count) {
    return '$count of 3 photos ready';
  }

  @override
  String get cropDoctorAddPhoto => 'Add another photo';

  @override
  String get cropDoctorRemovePhoto => 'Remove photo';

  @override
  String get cropDoctorCheckCrop => 'Check my crop';

  @override
  String get cropDoctorChooseCropTitle => 'Which crop is this?';

  @override
  String cropDoctorDetected(String crop) {
    return 'Looks like $crop. Tap another crop if this is wrong.';
  }

  @override
  String cropDoctorCropIs(String crop) {
    return 'Crop: $crop';
  }

  @override
  String get cropDoctorChangeCrop => 'Change crop';

  @override
  String get cropDoctorUnknownCrop => 'I don’t know';

  @override
  String get cropDoctorAskExpertToo => 'Also ask our expert';

  @override
  String get cropDoctorAnalysing => 'Checking your crop…';

  @override
  String get cropDoctorAnalysingHelp => 'This takes a few seconds';

  @override
  String get cropDoctorQueuedTitle => 'Saved on your phone';

  @override
  String get cropDoctorQueuedHelp => 'We’ll check when you’re online';

  @override
  String get cropDoctorSendFailed =>
      'Could not send your photos. Take them again.';

  @override
  String get cropDoctorResultTitle => 'Result';

  @override
  String get cropDoctorMessageAnswered => 'We found the problem';

  @override
  String get cropDoctorMessageProvisional =>
      'Provisional — expert will confirm';

  @override
  String get cropDoctorMessageUnknown =>
      'We are not sure yet. Our expert will look at your photos.';

  @override
  String get cropDoctorMessageConfirmed => 'Our expert confirmed this result';

  @override
  String get cropDoctorMessageCorrected => 'Our expert changed this result';

  @override
  String get cropDoctorOutNotPlant => 'We could not see a plant in the photo';

  @override
  String get cropDoctorOutUnsupportedCrop => 'We cannot check this crop yet';

  @override
  String get cropDoctorOutUnreadable => 'The photo was not clear enough';

  @override
  String get cropDoctorOutNoMatch => 'We could not find this problem';

  @override
  String get cropDoctorOutNotDiagnosable =>
      'Our expert could not tell from the photos';

  @override
  String get cropDoctorOutHelp =>
      'Our expert will look at it. You can also call your field officer.';

  @override
  String get cropDoctorTalkToOfficer => 'Talk to your field officer';

  @override
  String get cropDoctorCallOfficer => 'Call my officer';

  @override
  String get cropDoctorAskExpert => 'Ask an expert';

  @override
  String get cropDoctorAskExpertSent =>
      'Sent to our expert. We’ll tell you the answer.';

  @override
  String get cropDoctorAskExpertAlready => 'Our expert already has your photos';

  @override
  String get cropDoctorAskExpertFailed =>
      'Could not reach our expert. Check your internet and try again.';

  @override
  String get cropDoctorOrder => 'Order';

  @override
  String cropDoctorProductsAt(String store) {
    return 'Products at $store';
  }

  @override
  String cropDoctorStoreDistance(String store, String km) {
    return '$store, $km km';
  }

  @override
  String get cropDoctorCulturalTitle => 'Also do this';

  @override
  String get cropDoctorNoProducts =>
      'No product for this at your store yet. Talk to your field officer.';

  @override
  String get cropDoctorUpdatedTitle => 'Your result was updated';

  @override
  String get cropDoctorHistoryTitle => 'Earlier answers';

  @override
  String cropDoctorEarlierAnswer(String answer) {
    return 'Earlier: $answer';
  }

  @override
  String get cropDoctorMyChecks => 'My crop checks';

  @override
  String get cropDoctorWaiting => 'Waiting for the answer';

  @override
  String get cropDoctorSymptomsHelp => 'Tap the signs you see on your crop';

  @override
  String cropDoctorResultUpdatedHome(String problem) {
    return 'Crop check updated: $problem';
  }

  @override
  String get scoutTitle => 'Scout crop';

  @override
  String get scoutChoosePlot => 'Choose the crop plot';

  @override
  String get scoutNoPlots =>
      'This farmer has no crop plot yet. Add a farm and crop first.';

  @override
  String scoutPlotLine(String crop, String farm) {
    return '$crop · $farm';
  }

  @override
  String scoutAttachedTo(String farmer, String crop) {
    return 'For $farmer · $crop';
  }

  @override
  String get scoutCreateOrder => 'Create order for farmer';

  @override
  String get scoutCallFarmer => 'Call farmer';

  @override
  String get scoutQueuedHelp =>
      'Queued. It will be sent when the phone is online.';

  @override
  String scoutProvenance(String model, String corpus) {
    return 'Model $model · corpus v$corpus';
  }

  @override
  String get scoutNewDiagnosis => 'New diagnosis';

  @override
  String get scoutCheckPhotos => 'Check photos';

  @override
  String get kisanDeleteStatusRejected =>
      'Your request was not accepted. Please call your store.';

  @override
  String get cropDoctorNotOnPhone => 'This crop check is not on this phone';

  @override
  String get voiceStart => 'Speak';

  @override
  String get voiceStop => 'Stop';

  @override
  String get voiceListening => 'Listening…';

  @override
  String get voiceUnavailable =>
      'This phone has no voice typing. You can type instead.';

  @override
  String fieldAsOf(String time) {
    return 'As of $time';
  }

  @override
  String get fieldOfflineCached => 'Showing the last synced copy.';

  @override
  String get fieldPendingSync => 'Will sync';

  @override
  String get meSectionTitle => 'My work';

  @override
  String get settingsLogOut => 'Log out';

  @override
  String get settingsLogOutHelp =>
      'You will need your phone and an OTP to sign in again.';

  @override
  String get inboxTitle => 'Notifications';

  @override
  String get inboxEmpty => 'No notifications';

  @override
  String get inboxEmptyHelp =>
      'Visit confirmations, orders and approvals show up here.';

  @override
  String get inboxMarkAllRead => 'Mark all read';

  @override
  String inboxUnread(int count) {
    return '$count unread';
  }

  @override
  String get navInbox => 'Inbox';

  @override
  String get notifBeatPlanReadyTitle => 'Today\'s beat plan is ready';

  @override
  String get notifBeatPlanReadyBody => 'Open it to see today\'s farmers.';

  @override
  String get notifOrderStatusTitle => 'Order update';

  @override
  String get notifOrderStatusBody =>
      'The store changed the status of an order.';

  @override
  String get notifCreditApprovalTitle => 'Credit decision';

  @override
  String get notifCreditApprovalApproved => 'The credit sale was approved.';

  @override
  String get notifCreditApprovalRejected => 'The credit sale was not approved.';

  @override
  String get notifTravelClaimSubmittedTitle => 'New expense claim';

  @override
  String get notifTravelClaimSubmittedBody =>
      'An officer submitted an expense claim.';

  @override
  String get notifTravelClaimDecidedTitle => 'Expense claim decision';

  @override
  String get notifTravelClaimApproved => 'Your claim was approved.';

  @override
  String get notifTravelClaimRejected => 'Your claim was not approved.';

  @override
  String get notifFlagTitle => 'A flag about your work';

  @override
  String get notifFlagBody => 'Open My flags to add your explanation.';

  @override
  String get notifDutyAutoEndedBody => 'Your duty was ended automatically.';

  @override
  String get notifDiagnosisTitle => 'Crop check update';

  @override
  String get notifDiagnosisBody => 'An agronomist reviewed a crop check.';

  @override
  String get notifVisitConfirmTitle => 'Visit confirmation';

  @override
  String get notifVisitConfirmBody => 'A farmer confirmation is waiting.';

  @override
  String get notifGenericTitle => 'Update';

  @override
  String get notifGenericBody => 'Open to see the details.';

  @override
  String get beatTitle => 'Today\'s beat';

  @override
  String get beatEmpty => 'No beat plan yet';

  @override
  String get beatEmptyHelp =>
      'The plan arrives at 6:00 each morning. You can add farmers yourself.';

  @override
  String beatTarget(int done, int target) {
    return '$done of $target visited';
  }

  @override
  String get beatReasonFollowUp => 'Follow-up due';

  @override
  String get beatReasonPestAlert => 'Pest alert';

  @override
  String get beatReasonCreditDue => 'Credit due';

  @override
  String get beatReasonDemoStage => 'Demo stage due';

  @override
  String get beatShowMap => 'Map';

  @override
  String get beatShowList => 'List';

  @override
  String get beatAddVillage => 'Add village';

  @override
  String get beatRemove => 'Remove from beat';

  @override
  String get beatReorderHint => 'Press and hold a card to reorder';

  @override
  String get beatVillageKind => 'Village';

  @override
  String get myDayGapAddReason => 'Add reason';

  @override
  String get myDayGapSheetTitle => 'Why is there a gap?';

  @override
  String get myDayGapReasonNetwork => 'No network or GPS';

  @override
  String get myDayGapReasonBreak => 'Personal break';

  @override
  String get myDayGapReasonVehicle => 'Vehicle trouble';

  @override
  String get myDayGapReasonOther => 'Other';

  @override
  String get myDayGapNoteLabel => 'Note';

  @override
  String get myDayGapNoteHint => 'Say what happened';

  @override
  String myDayGapRange(String start, String end, int minutes) {
    return '$start – $end · $minutes min';
  }

  @override
  String get myDayGapReasonSaved => 'Reason saved. It will sync.';

  @override
  String get myDayManagerSeesReasons => 'Your cluster head sees these reasons.';

  @override
  String get myDayNoGaps => 'No gaps today';

  @override
  String myDayStops(int count) {
    return '$count stops';
  }

  @override
  String myDayVisitPins(int count) {
    return '$count visits';
  }

  @override
  String get myDayKmEstimated => 'Estimated on this phone';

  @override
  String get myDayKmProcessed => 'Processed by the server';

  @override
  String get performanceTitle => 'My performance';

  @override
  String get perfTargetsVsActual => 'Targets vs actual';

  @override
  String get perfNewFarmers => 'New farmers';

  @override
  String get perfSales => 'Sales';

  @override
  String get perfIncentive => 'Incentive earned';

  @override
  String get perfIncentivePending =>
      'Shown once your company activates the incentive rules.';

  @override
  String get perfTrendTitle => 'Verified visits, last 14 days';

  @override
  String perfOfTarget(String actual, String target) {
    return '$actual of $target';
  }

  @override
  String get perfNoTarget => 'No target set';

  @override
  String perfRank(int rank) {
    return 'Rank $rank in your cluster';
  }

  @override
  String get perfConfirmationRate => 'Farmer confirmations';

  @override
  String get perfEmpty => 'Nothing this month yet';

  @override
  String get perfEmptyHelp =>
      'Numbers appear once your visits and orders sync.';

  @override
  String get travelTitle => 'Travel allowance';

  @override
  String get travelKmByDay => 'Km by day';

  @override
  String get travelTaTotal => 'Allowance from km';

  @override
  String get travelPayable => 'Payable so far';

  @override
  String travelCapped(int cap) {
    return 'Capped at $cap km';
  }

  @override
  String travelDayKm(String km) {
    return '$km km';
  }

  @override
  String get travelClaimsTitle => 'Expense claims';

  @override
  String get travelAddClaim => 'Add expense';

  @override
  String get travelClaimType => 'Type';

  @override
  String get travelClaimTypeFuel => 'Fuel';

  @override
  String get travelClaimTypeBus => 'Bus fare';

  @override
  String get travelClaimTypeOther => 'Other';

  @override
  String get travelClaimAmount => 'Amount';

  @override
  String get travelClaimDate => 'Date of expense';

  @override
  String get travelClaimNote => 'Note';

  @override
  String get travelClaimReceipt => 'Receipt photo';

  @override
  String get travelClaimTakePhoto => 'Take receipt photo';

  @override
  String get travelClaimReceiptRequired => 'A receipt photo is required.';

  @override
  String get travelClaimAmountRequired => 'Enter an amount.';

  @override
  String get travelClaimQueued => 'Claim saved. It will sync.';

  @override
  String get travelClaimStatusQueued => 'Waiting to sync';

  @override
  String get travelClaimStatusSubmitted => 'With your cluster head';

  @override
  String get travelClaimStatusApproved => 'Approved';

  @override
  String get travelClaimStatusRejected => 'Not approved';

  @override
  String get travelEmpty => 'No travel this month yet';

  @override
  String get travelEmptyHelp => 'Go on duty; km and allowance appear here.';

  @override
  String get flagsTitle => 'My flags';

  @override
  String get flagsOpenSection => 'Open';

  @override
  String get flagsResolvedSection => 'Resolved';

  @override
  String get flagsEmpty => 'No flags about your work';

  @override
  String get flagsEmptyHelp => 'You only ever see flags about yourself.';

  @override
  String get flagAddExplanation => 'Add an explanation';

  @override
  String get flagExplanationLabel => 'Your explanation';

  @override
  String get flagExplanationHint => 'Say what happened that day';

  @override
  String get flagExplanationSent => 'Sent to your cluster head.';

  @override
  String get flagExplanationNeedsNetwork =>
      'You need a network connection to send an explanation.';

  @override
  String get flagOutcomeTitle => 'Outcome';

  @override
  String get flagOutcomeHidden =>
      'The outcome appears once this flag is resolved.';

  @override
  String get flagStateOpen => 'Open';

  @override
  String get flagStateInReview => 'In review';

  @override
  String get flagStateResolved => 'Resolved';

  @override
  String get flagSeverityLow => 'Low';

  @override
  String get flagSeverityMedium => 'Medium';

  @override
  String get flagSeverityHigh => 'High';

  @override
  String get meetingsTitle => 'Farmer meetings';

  @override
  String get meetingsEmpty => 'No meetings yet';

  @override
  String get meetingsEmptyHelp => 'Start one at the village meeting point.';

  @override
  String get meetingNew => 'New meeting';

  @override
  String get meetingTopic => 'Topic';

  @override
  String get meetingTopicHint => 'What the meeting is about';

  @override
  String get meetingNotes => 'Meeting notes';

  @override
  String get meetingStart => 'Start meeting';

  @override
  String get meetingAttendance => 'Attendance';

  @override
  String meetingAttendees(int count) {
    return '$count present';
  }

  @override
  String get meetingAddByOtp => 'Add by OTP';

  @override
  String get meetingAddByQr => 'Scan farmer QR';

  @override
  String meetingOtpSent(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get meetingOtpNeedsNetwork =>
      'OTP needs a network connection. Use the QR instead.';

  @override
  String get meetingFinish => 'Finish meeting';

  @override
  String get meetingClosed => 'Closed';

  @override
  String get meetingQrInvalid => 'That QR is not a farmer attendance code.';

  @override
  String get meetingAlreadyPresent => 'That farmer is already on the list.';

  @override
  String get demoTitle => 'Demo plots';

  @override
  String get demoEmpty => 'No demo plots yet';

  @override
  String get demoEmptyHelp => 'Register one on a farmer\'s crop plot.';

  @override
  String get demoNew => 'New demo plot';

  @override
  String get demoTreatment => 'Product or treatment';

  @override
  String get demoBaseline => 'Compare with';

  @override
  String get demoBaselinePractice => 'Farmer practice';

  @override
  String get demoBaselineComparison => 'Comparison plot';

  @override
  String get demoStatusCreated => 'Registered';

  @override
  String get demoStatusActive => 'Running';

  @override
  String get demoStatusHarvested => 'Harvested';

  @override
  String get demoStatusReported => 'Reported';

  @override
  String get demoStageSown => 'Sowing';

  @override
  String get demoStageVegetative => 'Vegetative';

  @override
  String get demoStageFlowering => 'Flowering';

  @override
  String get demoStageFruiting => 'Fruiting';

  @override
  String get demoStageMaturity => 'Maturity';

  @override
  String get demoStageHarvest => 'Harvest';

  @override
  String get demoAddObservation => 'Add stage observation';

  @override
  String get demoObservationNote => 'Observation';

  @override
  String get demoSide => 'Side';

  @override
  String get demoSideDemo => 'Demo';

  @override
  String get demoSideBoth => 'Both';

  @override
  String get demoTakePhoto => 'Add stage photo';

  @override
  String get demoEnterYield => 'Enter yield';

  @override
  String get demoYieldDemo => 'Demo yield (kg/acre)';

  @override
  String get demoYieldPractice => 'Farmer practice yield (kg/acre)';

  @override
  String demoYieldGain(String pct) {
    return '$pct% more than farmer practice';
  }

  @override
  String get demoStart => 'Start demo';

  @override
  String get demoReport => 'Mark reported';

  @override
  String get demoComparison => 'Demo vs farmer practice';

  @override
  String get visitVoiceInputSoon => 'Voice input arrives in a later update';

  @override
  String get kisanAddCrop => 'Add a crop';

  @override
  String get kisanCropCalendar => 'Crop calendar';

  @override
  String get kisanWeather => 'Weather';

  @override
  String get kisanAlerts => 'Pest alerts';

  @override
  String get kisanMessages => 'Messages';

  @override
  String get addCropTitle => 'Add a crop';

  @override
  String get addCropHelp => 'Tap the pictures. You do not need to type.';

  @override
  String get addCropWhichCrop => 'Which crop did you sow?';

  @override
  String get addCropWhichFarm => 'Which farm?';

  @override
  String get addCropWhenSown => 'When did you sow it?';

  @override
  String get addCropWater => 'How do you water it?';

  @override
  String get addCropSoil => 'What soil is it?';

  @override
  String get addCropSave => 'Save crop';

  @override
  String get addCropSaved => 'Crop added. Your calendar is ready.';

  @override
  String addCropSownOn(String date) {
    return 'Sown on $date';
  }

  @override
  String get addCropNoFarm => 'Add your farm first';

  @override
  String get calendarTitle => 'Crop calendar';

  @override
  String get calendarHelp =>
      'Your tasks week by week. Tap the speaker to listen.';

  @override
  String calendarWeek(int week) {
    return 'Week $week';
  }

  @override
  String calendarSownOn(String date) {
    return 'Sown on $date';
  }

  @override
  String calendarDueOn(String date) {
    return 'Do it on $date';
  }

  @override
  String calendarDueBetween(String from, String to) {
    return 'Do it between $from and $to';
  }

  @override
  String get calendarLate => 'Late';

  @override
  String get calendarMarkDone => 'Mark done';

  @override
  String get calendarDone => 'Done';

  @override
  String get calendarRemindMe => 'Remind me';

  @override
  String get calendarReminderOff => 'No reminder';

  @override
  String get calendarNoTasks => 'No tasks yet';

  @override
  String get calendarNoTasksHelp =>
      'Add the sowing date and your tasks will come.';

  @override
  String get calendarChangedTitle => 'Your calendar changed';

  @override
  String calendarChangedLater(int days, int count) {
    return 'Sowing moved $days days later, so $count tasks moved too.';
  }

  @override
  String calendarChangedEarlier(int days, int count) {
    return 'Sowing moved $days days earlier, so $count tasks moved too.';
  }

  @override
  String calendarChangedTasks(int count) {
    return '$count tasks changed.';
  }

  @override
  String get calendarChangedDoneKept =>
      'The work you already finished stays finished.';

  @override
  String get calendarGotIt => 'Got it';

  @override
  String calendarNextTask(String task) {
    return 'Next: $task';
  }

  @override
  String get calendarAllDone => 'All tasks done';

  @override
  String get calendarSavedOffline =>
      'Saved on this phone. It will be sent when you are online.';

  @override
  String get taskTypeSow => 'Sow';

  @override
  String get taskTypeIrrigate => 'Water';

  @override
  String get taskTypeFertilise => 'Fertiliser';

  @override
  String get taskTypeSpray => 'Spray';

  @override
  String get taskTypeHarvest => 'Harvest';

  @override
  String get weatherTitle => 'Weather';

  @override
  String get weatherSevenDays => 'Next 7 days';

  @override
  String weatherRainChance(int percent) {
    return 'Rain $percent%';
  }

  @override
  String weatherTempRange(String min, String max) {
    return '$min° to $max°';
  }

  @override
  String weatherWind(String speed) {
    return 'Wind $speed km/h';
  }

  @override
  String get weatherSprayTitle => 'When to spray';

  @override
  String get weatherSprayNextDays => 'Next 3 days';

  @override
  String get weatherSprayGood => 'Good time to spray';

  @override
  String get weatherSprayAvoid => 'Do not spray';

  @override
  String get weatherSprayNone => 'No good spray time in the next 3 days';

  @override
  String weatherWindowTime(String from, String to) {
    return '$from to $to';
  }

  @override
  String get weatherReasonRainLikely => 'Rain is likely';

  @override
  String get weatherReasonRain => 'It will rain';

  @override
  String get weatherReasonWindHigh => 'Wind is too strong';

  @override
  String get weatherCautionHeat => 'Very hot';

  @override
  String get weatherCautionHumidityHigh => 'Very humid';

  @override
  String get weatherCautionHumidityLow => 'Air is very dry';

  @override
  String get weatherAdviceOnly =>
      'This is advice only. Look at your field before you spray.';

  @override
  String get weatherNone => 'No weather for your farm yet';

  @override
  String get weatherNoneHelp =>
      'Your field officer can put your farm on the map.';

  @override
  String get weatherSkyClear => 'Clear';

  @override
  String get weatherSkyCloudy => 'Cloudy';

  @override
  String get weatherSkyFog => 'Fog';

  @override
  String get weatherSkyDrizzle => 'Light rain';

  @override
  String get weatherSkyRain => 'Rain';

  @override
  String get weatherSkyShowers => 'Heavy showers';

  @override
  String get weatherSkyThunder => 'Thunderstorm';

  @override
  String get alertsTitle => 'Pest alerts';

  @override
  String get alertsNone => 'No pest alerts in your district';

  @override
  String get alertsNoneHelp =>
      'We will tell you if a problem spreads near you.';

  @override
  String get alertSeverityHigh => 'High';

  @override
  String get alertSeverityMedium => 'Medium';

  @override
  String get alertSeverityLow => 'Low';

  @override
  String get alertGrowsCrop => 'You grow this crop';

  @override
  String alertFarmersAffected(int count) {
    return '$count farmers affected';
  }

  @override
  String alertWeekOf(String date) {
    return 'Week of $date';
  }

  @override
  String get alertLookForTitle => 'What to look for';

  @override
  String get alertDoTitle => 'What to do';

  @override
  String get alertCheckCrop => 'Take a photo of my crop';

  @override
  String get alertSeeProducts => 'See products at the store';

  @override
  String get alertDismiss => 'Hide this alert';

  @override
  String get alertHidden => 'Alert hidden';

  @override
  String get alertSignPestUnderLeaf =>
      'Look under the leaves for insects or eggs';

  @override
  String get alertSignPestHoles => 'Look for holes or chewed leaf edges';

  @override
  String get alertSignPestWilting => 'Look for drooping or dying shoots';

  @override
  String get alertSignDiseaseSpots => 'Look for spots on the leaves';

  @override
  String get alertSignDiseasePowder =>
      'Look for white or grey powder on the leaves';

  @override
  String get alertSignDiseaseRot => 'Look for rotting stems or fruit';

  @override
  String get alertSignDeficiencyColour => 'Look for yellow or pale leaves';

  @override
  String get alertSignDeficiencyGrowth =>
      'Look for slow growth or small leaves';

  @override
  String get alertSignWeedPatches => 'Look for weed patches between the plants';

  @override
  String get alertSignWalkField => 'Walk your field and look at 10 plants';

  @override
  String get farmerInboxTitle => 'Messages';

  @override
  String get farmerInboxEmpty => 'No messages yet';

  @override
  String get farmerInboxEmptyHelp =>
      'Crop check results, orders and alerts come here.';

  @override
  String get farmerInboxMarkAllRead => 'Mark all read';

  @override
  String farmerInboxUnread(int count) {
    return '$count new';
  }

  @override
  String get notifDiagnosisReadyTitle => 'Your crop check is ready';

  @override
  String get notifDiagnosisReadyBody =>
      'Tap to see the problem and what to do.';

  @override
  String get notifDiagnosisReviewedTitle => 'Our expert checked your photo';

  @override
  String get notifDiagnosisReviewedBody =>
      'The answer was updated. Tap to read it.';

  @override
  String get notifDiagnosisExpertTitle => 'An expert is looking at your photo';

  @override
  String get notifDiagnosisExpertBody => 'We will tell you within 24 hours.';

  @override
  String get farmerNotifOrderStatusTitle => 'Your order moved on';

  @override
  String get farmerNotifOrderStatusBody => 'Tap to see your order.';

  @override
  String get notifOutbreakAlertTitle => 'Pest alert in your district';

  @override
  String get notifOutbreakAlertBody => 'Check your field today.';

  @override
  String get notifCropTaskReminderTitle => 'A farm task is due today';

  @override
  String get notifCropTaskReminderBody => 'Tap to open your crop calendar.';

  @override
  String get farmerNotifVisitConfirmTitle => 'Did your officer visit?';

  @override
  String get farmerNotifVisitConfirmBody => 'Tap to answer yes or no.';

  @override
  String get farmerNotifGenericTitle => 'Update';

  @override
  String get farmerNotifGenericBody => 'Tap to see it.';

  @override
  String get mandiTitle => 'Mandi prices';

  @override
  String get mandiOpen => 'Mandi prices';

  @override
  String get mandiEmptyTitle => 'No prices yet';

  @override
  String get mandiEmptyHelp =>
      'Prices for your crops will appear here once the market publishes them.';

  @override
  String get mandiIndicative =>
      'These prices are only for your information. They come from a public market list, not from the store.';

  @override
  String mandiSource(String source) {
    return 'From $source';
  }

  @override
  String mandiPriceOn(String date) {
    return 'Price of $date';
  }

  @override
  String get mandiPerQuintal => 'per quintal';

  @override
  String mandiRange(String low, String high) {
    return '$low to $high';
  }

  @override
  String get mandiNoPriceYet => 'No price for this crop yet';

  @override
  String get referralTitle => 'Invite a farmer';

  @override
  String get referralOpen => 'Invite a farmer';

  @override
  String get referralIntro =>
      'Share your code with a farmer you know. When they join, you and your nearest store both get the reward.';

  @override
  String get referralYourCode => 'Your code';

  @override
  String get referralShareWhatsApp => 'Share on WhatsApp';

  @override
  String get referralShareSms => 'Send by SMS';

  @override
  String referralShareMessage(String link, String code) {
    return 'Join me on Kisan for crop advice and farm supplies. Open $link or use my code $code.';
  }

  @override
  String referralInvited(int count) {
    return '$count invited';
  }

  @override
  String referralJoined(int count) {
    return '$count joined';
  }

  @override
  String referralRewarded(int count) {
    return '$count rewarded';
  }

  @override
  String get referralRewardNone =>
      'Your store will tell you what the reward is.';

  @override
  String get referralOff => 'Invites are switched off right now.';

  @override
  String get referralClaimed => 'Thank you. Your invite has been counted.';

  @override
  String get referralClaimFailed => 'That invite could not be used.';
}
