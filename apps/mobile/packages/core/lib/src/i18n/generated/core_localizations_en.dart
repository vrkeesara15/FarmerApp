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
}
