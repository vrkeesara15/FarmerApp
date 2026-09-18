import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'core_localizations_en.dart';
import 'core_localizations_hi.dart';
import 'core_localizations_kn.dart';
import 'core_localizations_mr.dart';
import 'core_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of CoreLocalizations
/// returned by `CoreLocalizations.of(context)`.
///
/// Applications need to include `CoreLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/core_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: CoreLocalizations.localizationsDelegates,
///   supportedLocales: CoreLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the CoreLocalizations.supportedLocales
/// property.
abstract class CoreLocalizations {
  CoreLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static CoreLocalizations of(BuildContext context) {
    return Localizations.of<CoreLocalizations>(context, CoreLocalizations)!;
  }

  static const LocalizationsDelegate<CoreLocalizations> delegate =
      _CoreLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('kn'),
    Locale('mr'),
    Locale('te'),
  ];

  /// Field agent app name (brand, transliterate only)
  ///
  /// In en, this message translates to:
  /// **'Mitra'**
  String get appNameAgent;

  /// Farmer app name (brand, transliterate only)
  ///
  /// In en, this message translates to:
  /// **'Kisan'**
  String get appNameFarmer;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Trusted advice for your farm'**
  String get splashTagline;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @languagePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get languagePickerTitle;

  /// No description provided for @languagePickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap the speaker to hear it'**
  String get languagePickerSubtitle;

  /// Label next to the speaker icon on a language tile; shown in that tile's own language
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get languagePlayAudio;

  /// Script name; identical in every locale
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Script name; identical in every locale
  ///
  /// In en, this message translates to:
  /// **'తెలుగు'**
  String get languageTelugu;

  /// Script name; identical in every locale
  ///
  /// In en, this message translates to:
  /// **'ಕನ್ನಡ'**
  String get languageKannada;

  /// Script name; identical in every locale
  ///
  /// In en, this message translates to:
  /// **'हिन्दी'**
  String get languageHindi;

  /// Script name; identical in every locale
  ///
  /// In en, this message translates to:
  /// **'मराठी'**
  String get languageMarathi;

  /// Name of the English language in the current UI language (tile caption)
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglishName;

  /// No description provided for @languageTeluguName.
  ///
  /// In en, this message translates to:
  /// **'Telugu'**
  String get languageTeluguName;

  /// No description provided for @languageKannadaName.
  ///
  /// In en, this message translates to:
  /// **'Kannada'**
  String get languageKannadaName;

  /// No description provided for @languageHindiName.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get languageHindiName;

  /// No description provided for @languageMarathiName.
  ///
  /// In en, this message translates to:
  /// **'Marathi'**
  String get languageMarathiName;

  /// No description provided for @phoneLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get phoneLoginTitle;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get phoneLabel;

  /// No description provided for @phonePrefix.
  ///
  /// In en, this message translates to:
  /// **'+91'**
  String get phonePrefix;

  /// No description provided for @phoneHelper.
  ///
  /// In en, this message translates to:
  /// **'We will send a 6-digit OTP by SMS'**
  String get phoneHelper;

  /// No description provided for @phoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit mobile number'**
  String get phoneInvalid;

  /// No description provided for @phoneSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get phoneSendOtp;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the OTP'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sent to +91 {phone}'**
  String otpSubtitle(String phone);

  /// No description provided for @otpLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit OTP'**
  String get otpLabel;

  /// No description provided for @otpResend.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get otpResend;

  /// No description provided for @otpResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds} s'**
  String otpResendIn(int seconds);

  /// No description provided for @otpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Incorrect OTP. Please try again.'**
  String get otpInvalid;

  /// No description provided for @otpVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get otpVerify;

  /// Screen-reader label of one OTP box
  ///
  /// In en, this message translates to:
  /// **'Digit {index} of 6'**
  String otpDigitLabel(int index);

  /// No description provided for @otpAttemptsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} attempts left'**
  String otpAttemptsLeft(int count);

  /// No description provided for @otpLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong attempts. Try again in {minutes} min.'**
  String otpLocked(int minutes);

  /// No description provided for @otpRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many codes requested. Try again in {minutes} min.'**
  String otpRateLimited(int minutes);

  /// No description provided for @otpExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired. Request a new one.'**
  String get otpExpired;

  /// No description provided for @phoneNotFound.
  ///
  /// In en, this message translates to:
  /// **'This number is not registered. Ask your manager to add you.'**
  String get phoneNotFound;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your network and try again.'**
  String get networkError;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Your location and data'**
  String get consentTitle;

  /// No description provided for @consentPoint1.
  ///
  /// In en, this message translates to:
  /// **'We collect your location and visit photos.'**
  String get consentPoint1;

  /// No description provided for @consentPoint2.
  ///
  /// In en, this message translates to:
  /// **'Location is collected only while you are on duty.'**
  String get consentPoint2;

  /// No description provided for @consentPoint3.
  ///
  /// In en, this message translates to:
  /// **'It is used for travel allowance and visit credit.'**
  String get consentPoint3;

  /// No description provided for @consentPoint4.
  ///
  /// In en, this message translates to:
  /// **'Your manager and owner can see it. Farmers cannot.'**
  String get consentPoint4;

  /// No description provided for @consentAgree.
  ///
  /// In en, this message translates to:
  /// **'I agree'**
  String get consentAgree;

  /// No description provided for @consentPolicyLink.
  ///
  /// In en, this message translates to:
  /// **'Read the full policy'**
  String get consentPolicyLink;

  /// No description provided for @consentDataCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Use my data to give crop advice'**
  String get consentDataCardTitle;

  /// No description provided for @consentDataCardBody.
  ///
  /// In en, this message translates to:
  /// **'We look at your crop photos and farm details to help you.'**
  String get consentDataCardBody;

  /// No description provided for @consentRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get consentRequired;

  /// No description provided for @consentOffersCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Send me offers and tips'**
  String get consentOffersCardTitle;

  /// No description provided for @consentOffersCardBody.
  ///
  /// In en, this message translates to:
  /// **'Messages about products and farming tips.'**
  String get consentOffersCardBody;

  /// No description provided for @consentOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get consentOptional;

  /// No description provided for @consentReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get consentReadAloud;

  /// No description provided for @dutyOn.
  ///
  /// In en, this message translates to:
  /// **'On duty'**
  String get dutyOn;

  /// No description provided for @dutyOff.
  ///
  /// In en, this message translates to:
  /// **'Off duty'**
  String get dutyOff;

  /// No description provided for @dutyGoOn.
  ///
  /// In en, this message translates to:
  /// **'Go on duty'**
  String get dutyGoOn;

  /// No description provided for @dutyGoOff.
  ///
  /// In en, this message translates to:
  /// **'Go off duty'**
  String get dutyGoOff;

  /// No description provided for @dutyElapsed.
  ///
  /// In en, this message translates to:
  /// **'On duty for {duration}'**
  String dutyElapsed(String duration);

  /// No description provided for @dutyLocationNote.
  ///
  /// In en, this message translates to:
  /// **'Location is on only while you are on duty'**
  String get dutyLocationNote;

  /// No description provided for @syncSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncSynced;

  /// No description provided for @syncPending.
  ///
  /// In en, this message translates to:
  /// **'Pending {count}'**
  String syncPending(int count);

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get syncFailed;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Your work is saved and will sync later.'**
  String get offlineBanner;

  /// No description provided for @syncSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncSyncing;

  /// No description provided for @syncDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync details'**
  String get syncDetailsTitle;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncLastSync.
  ///
  /// In en, this message translates to:
  /// **'Last synced {time}'**
  String syncLastSync(String time);

  /// No description provided for @syncNeverSynced.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get syncNeverSynced;

  /// No description provided for @syncAllDone.
  ///
  /// In en, this message translates to:
  /// **'Everything is synced'**
  String get syncAllDone;

  /// No description provided for @syncAllDoneHelp.
  ///
  /// In en, this message translates to:
  /// **'New farmers, farms and photos saved offline appear here until they reach the server.'**
  String get syncAllDoneHelp;

  /// No description provided for @syncPendingSection.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync ({count})'**
  String syncPendingSection(int count);

  /// No description provided for @syncFailedSection.
  ///
  /// In en, this message translates to:
  /// **'Needs attention ({count})'**
  String syncFailedSection(int count);

  /// No description provided for @syncWaitingForPhoto.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the photo to upload'**
  String get syncWaitingForPhoto;

  /// No description provided for @syncPhotoUploads.
  ///
  /// In en, this message translates to:
  /// **'Photos uploading: {count}'**
  String syncPhotoUploads(int count);

  /// No description provided for @syncTransportError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. It will try again on its own.'**
  String get syncTransportError;

  /// No description provided for @syncNextAttempt.
  ///
  /// In en, this message translates to:
  /// **'Next attempt {time}'**
  String syncNextAttempt(String time);

  /// No description provided for @syncItemTitle.
  ///
  /// In en, this message translates to:
  /// **'{action} {entity}'**
  String syncItemTitle(String action, String entity);

  /// No description provided for @syncActionCreate.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get syncActionCreate;

  /// No description provided for @syncActionUpdate.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get syncActionUpdate;

  /// No description provided for @syncActionDelete.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get syncActionDelete;

  /// No description provided for @syncEntityFarmer.
  ///
  /// In en, this message translates to:
  /// **'farmer'**
  String get syncEntityFarmer;

  /// No description provided for @syncEntityFarm.
  ///
  /// In en, this message translates to:
  /// **'farm'**
  String get syncEntityFarm;

  /// No description provided for @syncEntityCropPlot.
  ///
  /// In en, this message translates to:
  /// **'crop plot'**
  String get syncEntityCropPlot;

  /// No description provided for @syncEntityConsent.
  ///
  /// In en, this message translates to:
  /// **'consent'**
  String get syncEntityConsent;

  /// No description provided for @syncEntityOther.
  ///
  /// In en, this message translates to:
  /// **'item'**
  String get syncEntityOther;

  /// No description provided for @syncSavedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved {time}'**
  String syncSavedAt(String time);

  /// No description provided for @syncRejectedDefault.
  ///
  /// In en, this message translates to:
  /// **'The server did not accept this item. Edit it and retry.'**
  String get syncRejectedDefault;

  /// No description provided for @syncRetryAll.
  ///
  /// In en, this message translates to:
  /// **'Retry all'**
  String get syncRetryAll;

  /// No description provided for @syncDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get syncDiscard;

  /// No description provided for @visitVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get visitVerified;

  /// No description provided for @visitPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get visitPartial;

  /// No description provided for @visitUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get visitUnverified;

  /// No description provided for @visitScore.
  ///
  /// In en, this message translates to:
  /// **'Score {score} of 100'**
  String visitScore(int score);

  /// No description provided for @visitDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String visitDurationMinutes(int minutes);

  /// No description provided for @visitPurposeAdvisory.
  ///
  /// In en, this message translates to:
  /// **'Advisory'**
  String get visitPurposeAdvisory;

  /// Visit purpose: walking the field to look for pests and disease
  ///
  /// In en, this message translates to:
  /// **'Scouting'**
  String get visitPurposeScouting;

  /// Visit purpose: product demonstration plot
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get visitPurposeDemo;

  /// Visit purpose: collecting a payment
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get visitPurposeCollection;

  /// No description provided for @visitPurposeSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get visitPurposeSale;

  /// No description provided for @visitPurposeMeeting.
  ///
  /// In en, this message translates to:
  /// **'Meeting'**
  String get visitPurposeMeeting;

  /// No description provided for @proofGeofence.
  ///
  /// In en, this message translates to:
  /// **'Inside farm boundary'**
  String get proofGeofence;

  /// No description provided for @proofGeofenceMissing.
  ///
  /// In en, this message translates to:
  /// **'You were outside the farm boundary'**
  String get proofGeofenceMissing;

  /// No description provided for @proofPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo taken'**
  String get proofPhoto;

  /// No description provided for @proofPhotoMissing.
  ///
  /// In en, this message translates to:
  /// **'No photo taken during the visit'**
  String get proofPhotoMissing;

  /// No description provided for @proofFarmerConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Farmer confirmed'**
  String get proofFarmerConfirmed;

  /// No description provided for @proofFarmerConfirmedMissing.
  ///
  /// In en, this message translates to:
  /// **'Farmer did not confirm the visit'**
  String get proofFarmerConfirmedMissing;

  /// No description provided for @proofDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum time on farm met'**
  String get proofDuration;

  /// No description provided for @proofDurationMissing.
  ///
  /// In en, this message translates to:
  /// **'Visit was shorter than 10 minutes'**
  String get proofDurationMissing;

  /// No description provided for @proofDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get proofDone;

  /// No description provided for @proofMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get proofMissing;

  /// No description provided for @cameraHoldSteady.
  ///
  /// In en, this message translates to:
  /// **'Hold steady'**
  String get cameraHoldSteady;

  /// No description provided for @cameraGoodLight.
  ///
  /// In en, this message translates to:
  /// **'Good light'**
  String get cameraGoodLight;

  /// No description provided for @cameraFillFrame.
  ///
  /// In en, this message translates to:
  /// **'Fill the frame'**
  String get cameraFillFrame;

  /// No description provided for @cameraLeafFrame.
  ///
  /// In en, this message translates to:
  /// **'Place the leaf inside the frame'**
  String get cameraLeafFrame;

  /// No description provided for @photoReviewHeading.
  ///
  /// In en, this message translates to:
  /// **'Check your photo'**
  String get photoReviewHeading;

  /// No description provided for @photoReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo {index} of {total}'**
  String photoReviewTitle(int index, int total);

  /// No description provided for @photoQualityOk.
  ///
  /// In en, this message translates to:
  /// **'Good photo'**
  String get photoQualityOk;

  /// No description provided for @photoQualityBlurry.
  ///
  /// In en, this message translates to:
  /// **'Blurry'**
  String get photoQualityBlurry;

  /// No description provided for @photoQualityDark.
  ///
  /// In en, this message translates to:
  /// **'Too dark'**
  String get photoQualityDark;

  /// No description provided for @photoQualityChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking photo'**
  String get photoQualityChecking;

  /// Retake tip for key photo.tip.blurry (FM-004)
  ///
  /// In en, this message translates to:
  /// **'Hold the phone steady, tap the leaf to focus and take it again'**
  String get photoTipBlurry;

  /// Retake tip for key photo.tip.dark (FM-004)
  ///
  /// In en, this message translates to:
  /// **'Move into better light, away from shade, and take it again'**
  String get photoTipDark;

  /// Line for key photo.tip.ok
  ///
  /// In en, this message translates to:
  /// **'Photo looks good'**
  String get photoTipOk;

  /// No description provided for @photoRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get photoRetake;

  /// No description provided for @photoUse.
  ///
  /// In en, this message translates to:
  /// **'Use photo'**
  String get photoUse;

  /// No description provided for @photoSizeKb.
  ///
  /// In en, this message translates to:
  /// **'{kb} KB'**
  String photoSizeKb(int kb);

  /// No description provided for @photoDimensions.
  ///
  /// In en, this message translates to:
  /// **'{width} × {height} px'**
  String photoDimensions(int width, int height);

  /// No description provided for @confidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'High confidence'**
  String get confidenceHigh;

  /// No description provided for @confidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium confidence'**
  String get confidenceMedium;

  /// Diagnosis not yet confirmed by an expert
  ///
  /// In en, this message translates to:
  /// **'Provisional'**
  String get confidenceLow;

  /// No description provided for @diagnosisSymptomsTitle.
  ///
  /// In en, this message translates to:
  /// **'Check these signs'**
  String get diagnosisSymptomsTitle;

  /// No description provided for @diagnosisProvisionalNote.
  ///
  /// In en, this message translates to:
  /// **'Our expert will confirm within 24 hours'**
  String get diagnosisProvisionalNote;

  /// No description provided for @diagnosisProblem.
  ///
  /// In en, this message translates to:
  /// **'Problem'**
  String get diagnosisProblem;

  /// No description provided for @treatmentOrganic.
  ///
  /// In en, this message translates to:
  /// **'Organic'**
  String get treatmentOrganic;

  /// No description provided for @treatmentChemical.
  ///
  /// In en, this message translates to:
  /// **'Chemical'**
  String get treatmentChemical;

  /// No description provided for @treatmentActiveIngredient.
  ///
  /// In en, this message translates to:
  /// **'Active ingredient'**
  String get treatmentActiveIngredient;

  /// No description provided for @treatmentDosePerAcre.
  ///
  /// In en, this message translates to:
  /// **'Per acre'**
  String get treatmentDosePerAcre;

  /// No description provided for @treatmentDosePerTank.
  ///
  /// In en, this message translates to:
  /// **'Per 15 L tank'**
  String get treatmentDosePerTank;

  /// No description provided for @treatmentSafetyInterval.
  ///
  /// In en, this message translates to:
  /// **'Wait {days} days before harvest'**
  String treatmentSafetyInterval(int days);

  /// No description provided for @treatmentPpeGloves.
  ///
  /// In en, this message translates to:
  /// **'Gloves'**
  String get treatmentPpeGloves;

  /// No description provided for @treatmentPpeMask.
  ///
  /// In en, this message translates to:
  /// **'Mask'**
  String get treatmentPpeMask;

  /// No description provided for @treatmentPpeGoggles.
  ///
  /// In en, this message translates to:
  /// **'Goggles'**
  String get treatmentPpeGoggles;

  /// Heading before the protective-equipment icons
  ///
  /// In en, this message translates to:
  /// **'Wear'**
  String get treatmentPpeTitle;

  /// Badge on products of the shop's own brand
  ///
  /// In en, this message translates to:
  /// **'Own brand'**
  String get ownBrand;

  /// No description provided for @productAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get productAdd;

  /// No description provided for @productAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get productAdded;

  /// No description provided for @productStockAtStore.
  ///
  /// In en, this message translates to:
  /// **'{count} in stock at {store}'**
  String productStockAtStore(int count, String store);

  /// No description provided for @productOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get productOutOfStock;

  /// Pack size label, e.g. 500 ml
  ///
  /// In en, this message translates to:
  /// **'Pack'**
  String get productPack;

  /// No description provided for @cartItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String cartItems(int count);

  /// No description provided for @cartTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get cartTotal;

  /// No description provided for @cartCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get cartCheckout;

  /// No description provided for @paymentMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'How will you pay?'**
  String get paymentMethodTitle;

  /// No description provided for @paymentUpiQr.
  ///
  /// In en, this message translates to:
  /// **'UPI QR'**
  String get paymentUpiQr;

  /// No description provided for @paymentUpiQrHint.
  ///
  /// In en, this message translates to:
  /// **'Scan and pay now'**
  String get paymentUpiQrHint;

  /// No description provided for @paymentLink.
  ///
  /// In en, this message translates to:
  /// **'Payment link'**
  String get paymentLink;

  /// No description provided for @paymentLinkHint.
  ///
  /// In en, this message translates to:
  /// **'Send by SMS or WhatsApp'**
  String get paymentLinkHint;

  /// No description provided for @paymentCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentCash;

  /// No description provided for @paymentCashHint.
  ///
  /// In en, this message translates to:
  /// **'Collect cash and give a receipt'**
  String get paymentCashHint;

  /// Pay later; amount goes to the farmer's khata (ledger)
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get paymentCredit;

  /// No description provided for @paymentCreditHint.
  ///
  /// In en, this message translates to:
  /// **'Add to farmer khata'**
  String get paymentCreditHint;

  /// No description provided for @upiWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment'**
  String get upiWaiting;

  /// No description provided for @upiPaid.
  ///
  /// In en, this message translates to:
  /// **'Payment received'**
  String get upiPaid;

  /// No description provided for @upiFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get upiFailed;

  /// No description provided for @upiExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {time}'**
  String upiExpiresIn(String time);

  /// No description provided for @upiAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get upiAmount;

  /// No description provided for @upiScanHint.
  ///
  /// In en, this message translates to:
  /// **'Ask the farmer to scan with any UPI app'**
  String get upiScanHint;

  /// No description provided for @upiRetry.
  ///
  /// In en, this message translates to:
  /// **'Show a new QR'**
  String get upiRetry;

  /// No description provided for @khataBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance due'**
  String get khataBalance;

  /// No description provided for @khataDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due on {date}'**
  String khataDueDate(String date);

  /// No description provided for @khataDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get khataDebit;

  /// Ledger column: money received from the farmer
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get khataCredit;

  /// No description provided for @khataNoEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get khataNoEntries;

  /// No description provided for @khataPayNow.
  ///
  /// In en, this message translates to:
  /// **'Pay now'**
  String get khataPayNow;

  /// No description provided for @khataCollect.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get khataCollect;

  /// No description provided for @emptyDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyDefaultTitle;

  /// No description provided for @emptyDefaultHelp.
  ///
  /// In en, this message translates to:
  /// **'Items will appear here once you add them.'**
  String get emptyDefaultHelp;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @errorHelp.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get errorHelp;

  /// No description provided for @ratingTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate your visit'**
  String get ratingTitle;

  /// No description provided for @rating1.
  ///
  /// In en, this message translates to:
  /// **'Very bad'**
  String get rating1;

  /// No description provided for @rating2.
  ///
  /// In en, this message translates to:
  /// **'Bad'**
  String get rating2;

  /// No description provided for @rating3.
  ///
  /// In en, this message translates to:
  /// **'Okay'**
  String get rating3;

  /// No description provided for @rating4.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get rating4;

  /// No description provided for @rating5.
  ///
  /// In en, this message translates to:
  /// **'Very good'**
  String get rating5;

  /// No description provided for @stepperStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String stepperStepOf(int current, int total);

  /// No description provided for @farmerLastVisit.
  ///
  /// In en, this message translates to:
  /// **'Last visit {date}'**
  String farmerLastVisit(String date);

  /// No description provided for @farmerNoVisit.
  ///
  /// In en, this message translates to:
  /// **'No visit yet'**
  String get farmerNoVisit;

  /// No description provided for @farmerBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'Due {amount}'**
  String farmerBalanceDue(String amount);

  /// No description provided for @farmerVillage.
  ///
  /// In en, this message translates to:
  /// **'Village'**
  String get farmerVillage;

  /// No description provided for @statTrendUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get statTrendUp;

  /// No description provided for @statTrendDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get statTrendDown;

  /// No description provided for @statTrendFlat.
  ///
  /// In en, this message translates to:
  /// **'No change'**
  String get statTrendFlat;

  /// No description provided for @stageSowing.
  ///
  /// In en, this message translates to:
  /// **'Sowing'**
  String get stageSowing;

  /// No description provided for @stageVegetative.
  ///
  /// In en, this message translates to:
  /// **'Growing'**
  String get stageVegetative;

  /// No description provided for @stageFlowering.
  ///
  /// In en, this message translates to:
  /// **'Flowering'**
  String get stageFlowering;

  /// No description provided for @stageFruiting.
  ///
  /// In en, this message translates to:
  /// **'Fruiting'**
  String get stageFruiting;

  /// No description provided for @stageHarvest.
  ///
  /// In en, this message translates to:
  /// **'Harvest'**
  String get stageHarvest;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// High-contrast theme for use outdoors in bright sun
  ///
  /// In en, this message translates to:
  /// **'Sunlight'**
  String get themeSunlight;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @skeletonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading content'**
  String get skeletonLoading;

  /// No description provided for @farmersTitle.
  ///
  /// In en, this message translates to:
  /// **'Farmers'**
  String get farmersTitle;

  /// No description provided for @farmersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name, phone or village'**
  String get farmersSearchHint;

  /// No description provided for @farmersAddFarmer.
  ///
  /// In en, this message translates to:
  /// **'Add farmer'**
  String get farmersAddFarmer;

  /// No description provided for @farmersEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No farmers yet'**
  String get farmersEmptyTitle;

  /// No description provided for @farmersEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Add your first farmer to start visits and orders.'**
  String get farmersEmptyHelp;

  /// No description provided for @farmersNoResults.
  ///
  /// In en, this message translates to:
  /// **'No farmers match your search'**
  String get farmersNoResults;

  /// No description provided for @farmersFilterVillage.
  ///
  /// In en, this message translates to:
  /// **'Village'**
  String get farmersFilterVillage;

  /// No description provided for @farmersFilterCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get farmersFilterCrop;

  /// No description provided for @farmersFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get farmersFilterAll;

  /// No description provided for @farmersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} farmers'**
  String farmersCount(int count);

  /// No description provided for @farmerPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Will sync when online'**
  String get farmerPendingSync;

  /// No description provided for @farmerPhoneUnverified.
  ///
  /// In en, this message translates to:
  /// **'Phone not verified'**
  String get farmerPhoneUnverified;

  /// No description provided for @farmerRejected.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get farmerRejected;

  /// No description provided for @regTitle.
  ///
  /// In en, this message translates to:
  /// **'Add farmer'**
  String get regTitle;

  /// No description provided for @regStepBasics.
  ///
  /// In en, this message translates to:
  /// **'Farmer details'**
  String get regStepBasics;

  /// No description provided for @regStepBoundary.
  ///
  /// In en, this message translates to:
  /// **'Farm boundary'**
  String get regStepBoundary;

  /// No description provided for @regStepCrops.
  ///
  /// In en, this message translates to:
  /// **'Crops'**
  String get regStepCrops;

  /// No description provided for @regStepConsent.
  ///
  /// In en, this message translates to:
  /// **'Consent'**
  String get regStepConsent;

  /// No description provided for @regStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review and save'**
  String get regStepReview;

  /// No description provided for @regResumeDraft.
  ///
  /// In en, this message translates to:
  /// **'Continuing where you left off'**
  String get regResumeDraft;

  /// No description provided for @regDiscardDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get regDiscardDraft;

  /// No description provided for @regFixIssues.
  ///
  /// In en, this message translates to:
  /// **'Fix the highlighted fields to continue'**
  String get regFixIssues;

  /// No description provided for @regNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Farmer name'**
  String get regNameLabel;

  /// No description provided for @regNameHint.
  ///
  /// In en, this message translates to:
  /// **'As on the ID card'**
  String get regNameHint;

  /// No description provided for @regPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Farmer mobile number'**
  String get regPhoneLabel;

  /// No description provided for @regPhoneHelper.
  ///
  /// In en, this message translates to:
  /// **'An OTP will be sent to the farmer'**
  String get regPhoneHelper;

  /// No description provided for @regSendOtpToFarmer.
  ///
  /// In en, this message translates to:
  /// **'Send OTP to farmer'**
  String get regSendOtpToFarmer;

  /// No description provided for @regOtpSent.
  ///
  /// In en, this message translates to:
  /// **'OTP sent to the farmer. Ask them for the code.'**
  String get regOtpSent;

  /// No description provided for @regPhoneVerified.
  ///
  /// In en, this message translates to:
  /// **'Phone verified'**
  String get regPhoneVerified;

  /// No description provided for @regVerifyLater.
  ///
  /// In en, this message translates to:
  /// **'Verify later'**
  String get regVerifyLater;

  /// No description provided for @regVerifyLaterNote.
  ///
  /// In en, this message translates to:
  /// **'No signal? Save now and verify the phone from the farmer profile.'**
  String get regVerifyLaterNote;

  /// No description provided for @regVerifyLaterChosen.
  ///
  /// In en, this message translates to:
  /// **'Will be verified later'**
  String get regVerifyLaterChosen;

  /// No description provided for @regDuplicatePhone.
  ///
  /// In en, this message translates to:
  /// **'A farmer with this number already exists'**
  String get regDuplicatePhone;

  /// No description provided for @regDuplicateOpen.
  ///
  /// In en, this message translates to:
  /// **'Open existing farmer'**
  String get regDuplicateOpen;

  /// No description provided for @regVillageLabel.
  ///
  /// In en, this message translates to:
  /// **'Village'**
  String get regVillageLabel;

  /// No description provided for @regVillageHint.
  ///
  /// In en, this message translates to:
  /// **'Choose the village'**
  String get regVillageHint;

  /// No description provided for @regVillageTyped.
  ///
  /// In en, this message translates to:
  /// **'Village name'**
  String get regVillageTyped;

  /// No description provided for @regVillageNoneSynced.
  ///
  /// In en, this message translates to:
  /// **'Villages will load after the first sync. Type the village name for now.'**
  String get regVillageNoneSynced;

  /// No description provided for @regLandmarkLabel.
  ///
  /// In en, this message translates to:
  /// **'Landmark'**
  String get regLandmarkLabel;

  /// No description provided for @regLandmarkHint.
  ///
  /// In en, this message translates to:
  /// **'Near the temple, school…'**
  String get regLandmarkHint;

  /// No description provided for @regLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language of the farmer'**
  String get regLanguageLabel;

  /// No description provided for @regOwnershipLabel.
  ///
  /// In en, this message translates to:
  /// **'Land'**
  String get regOwnershipLabel;

  /// No description provided for @regBoundaryWalk.
  ///
  /// In en, this message translates to:
  /// **'Walk around'**
  String get regBoundaryWalk;

  /// No description provided for @regBoundaryTap.
  ///
  /// In en, this message translates to:
  /// **'Tap corners'**
  String get regBoundaryTap;

  /// No description provided for @regStartWalk.
  ///
  /// In en, this message translates to:
  /// **'Start walking'**
  String get regStartWalk;

  /// No description provided for @regStopWalk.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get regStopWalk;

  /// No description provided for @regClosePolygon.
  ///
  /// In en, this message translates to:
  /// **'Close boundary'**
  String get regClosePolygon;

  /// No description provided for @regUndoPoint.
  ///
  /// In en, this message translates to:
  /// **'Undo point'**
  String get regUndoPoint;

  /// No description provided for @regClearBoundary.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get regClearBoundary;

  /// No description provided for @regPointsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} points'**
  String regPointsCount(int count);

  /// No description provided for @regAccuracy.
  ///
  /// In en, this message translates to:
  /// **'GPS accuracy ±{metres} m'**
  String regAccuracy(int metres);

  /// No description provided for @regAccuracyWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for GPS…'**
  String get regAccuracyWaiting;

  /// No description provided for @regLocationOff.
  ///
  /// In en, this message translates to:
  /// **'Turn on location to walk the boundary'**
  String get regLocationOff;

  /// No description provided for @regLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission is needed to walk the boundary'**
  String get regLocationDenied;

  /// No description provided for @regTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the four corners of the farm on the map'**
  String get regTapHint;

  /// No description provided for @regWalkHint.
  ///
  /// In en, this message translates to:
  /// **'Walk along the edge of the farm. Points are added as you go.'**
  String get regWalkHint;

  /// No description provided for @regComputedArea.
  ///
  /// In en, this message translates to:
  /// **'Measured area {acres} acres'**
  String regComputedArea(String acres);

  /// No description provided for @regAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'Area in acres'**
  String get regAreaLabel;

  /// No description provided for @regAreaHint.
  ///
  /// In en, this message translates to:
  /// **'As the farmer says'**
  String get regAreaHint;

  /// No description provided for @regUseMeasured.
  ///
  /// In en, this message translates to:
  /// **'Use measured'**
  String get regUseMeasured;

  /// No description provided for @regAreaWarning.
  ///
  /// In en, this message translates to:
  /// **'The entered area differs from the measured area by more than 30%. Check it before saving.'**
  String get regAreaWarning;

  /// No description provided for @regBoundaryInvalid.
  ///
  /// In en, this message translates to:
  /// **'The boundary crosses itself. Undo the last points and try again.'**
  String get regBoundaryInvalid;

  /// No description provided for @regFarmNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Farm name (optional)'**
  String get regFarmNameLabel;

  /// No description provided for @regFarmNameHint.
  ///
  /// In en, this message translates to:
  /// **'Home farm'**
  String get regFarmNameHint;

  /// No description provided for @regSoilLabel.
  ///
  /// In en, this message translates to:
  /// **'Soil type'**
  String get regSoilLabel;

  /// No description provided for @regIrrigationLabel.
  ///
  /// In en, this message translates to:
  /// **'Irrigation'**
  String get regIrrigationLabel;

  /// No description provided for @regFarmPhoto.
  ///
  /// In en, this message translates to:
  /// **'Farm photo (optional)'**
  String get regFarmPhoto;

  /// No description provided for @regTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get regTakePhoto;

  /// No description provided for @regPhotoAdded.
  ///
  /// In en, this message translates to:
  /// **'Photo added'**
  String get regPhotoAdded;

  /// No description provided for @regPhotoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get regPhotoRemove;

  /// No description provided for @regFarmPhotosCount.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String regFarmPhotosCount(int count);

  /// No description provided for @regCropsHelp.
  ///
  /// In en, this message translates to:
  /// **'Add every crop growing on this farm this season.'**
  String get regCropsHelp;

  /// No description provided for @regAddCrop.
  ///
  /// In en, this message translates to:
  /// **'Add crop'**
  String get regAddCrop;

  /// No description provided for @regCropLabel.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get regCropLabel;

  /// No description provided for @regVarietyLabel.
  ///
  /// In en, this message translates to:
  /// **'Variety'**
  String get regVarietyLabel;

  /// No description provided for @regVarietyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. MTU-1010'**
  String get regVarietyHint;

  /// No description provided for @regSowingDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Sowing date'**
  String get regSowingDateLabel;

  /// No description provided for @regSowingDateHint.
  ///
  /// In en, this message translates to:
  /// **'DD-MM-YYYY'**
  String get regSowingDateHint;

  /// No description provided for @regSeasonAuto.
  ///
  /// In en, this message translates to:
  /// **'Season: {season}'**
  String regSeasonAuto(String season);

  /// No description provided for @regPlotAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'Area (acres, optional)'**
  String get regPlotAreaLabel;

  /// No description provided for @regRemoveCrop.
  ///
  /// In en, this message translates to:
  /// **'Remove crop'**
  String get regRemoveCrop;

  /// No description provided for @regPlotTitle.
  ///
  /// In en, this message translates to:
  /// **'Crop {index}'**
  String regPlotTitle(int index);

  /// No description provided for @regAddFarm.
  ///
  /// In en, this message translates to:
  /// **'Add another farm'**
  String get regAddFarm;

  /// No description provided for @regFarmsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} farms'**
  String regFarmsCount(int count);

  /// No description provided for @regFarmIndex.
  ///
  /// In en, this message translates to:
  /// **'Farm {index}'**
  String regFarmIndex(int index);

  /// No description provided for @regConsentIntro.
  ///
  /// In en, this message translates to:
  /// **'Read this to the farmer in their language.'**
  String get regConsentIntro;

  /// No description provided for @regConsentNotice.
  ///
  /// In en, this message translates to:
  /// **'We will keep your name, phone, village and farm details to give you crop advice and keep visit records. You can ask us to stop at any time.'**
  String get regConsentNotice;

  /// No description provided for @regConsentMarketingNotice.
  ///
  /// In en, this message translates to:
  /// **'With your permission we will also send offers and farming tips by SMS or WhatsApp.'**
  String get regConsentMarketingNotice;

  /// No description provided for @regConsentGiven.
  ///
  /// In en, this message translates to:
  /// **'Farmer agrees'**
  String get regConsentGiven;

  /// No description provided for @regReviewFarmer.
  ///
  /// In en, this message translates to:
  /// **'Farmer'**
  String get regReviewFarmer;

  /// No description provided for @regReviewFarms.
  ///
  /// In en, this message translates to:
  /// **'Farms and crops'**
  String get regReviewFarms;

  /// No description provided for @regReviewConsent.
  ///
  /// In en, this message translates to:
  /// **'Consent'**
  String get regReviewConsent;

  /// No description provided for @regReviewSyncNote.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone now; sent to the server when the network is back.'**
  String get regReviewSyncNote;

  /// No description provided for @regSave.
  ///
  /// In en, this message translates to:
  /// **'Save farmer'**
  String get regSave;

  /// No description provided for @regSaveFarm.
  ///
  /// In en, this message translates to:
  /// **'Save farm'**
  String get regSaveFarm;

  /// No description provided for @regEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get regEdit;

  /// No description provided for @regSaved.
  ///
  /// In en, this message translates to:
  /// **'Farmer saved'**
  String get regSaved;

  /// No description provided for @regIssueName.
  ///
  /// In en, this message translates to:
  /// **'Enter the farmer name'**
  String get regIssueName;

  /// No description provided for @regIssuePhoneUnverified.
  ///
  /// In en, this message translates to:
  /// **'Verify the phone or choose Verify later'**
  String get regIssuePhoneUnverified;

  /// No description provided for @regIssueVillage.
  ///
  /// In en, this message translates to:
  /// **'Choose the village'**
  String get regIssueVillage;

  /// No description provided for @regIssueLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose the language of the farmer'**
  String get regIssueLanguage;

  /// No description provided for @regIssueBoundary.
  ///
  /// In en, this message translates to:
  /// **'Mark at least 3 points of the boundary'**
  String get regIssueBoundary;

  /// No description provided for @regIssueArea.
  ///
  /// In en, this message translates to:
  /// **'Enter the area in acres'**
  String get regIssueArea;

  /// No description provided for @regIssueCrop.
  ///
  /// In en, this message translates to:
  /// **'Add at least one crop'**
  String get regIssueCrop;

  /// No description provided for @regIssueSowingDate.
  ///
  /// In en, this message translates to:
  /// **'Enter the sowing date for every crop'**
  String get regIssueSowingDate;

  /// No description provided for @regIssueConsent.
  ///
  /// In en, this message translates to:
  /// **'Data consent is required to register'**
  String get regIssueConsent;

  /// No description provided for @soilBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get soilBlack;

  /// No description provided for @soilRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get soilRed;

  /// No description provided for @soilSandy.
  ///
  /// In en, this message translates to:
  /// **'Sandy'**
  String get soilSandy;

  /// No description provided for @soilLoamy.
  ///
  /// In en, this message translates to:
  /// **'Loamy'**
  String get soilLoamy;

  /// No description provided for @soilClay.
  ///
  /// In en, this message translates to:
  /// **'Clay'**
  String get soilClay;

  /// No description provided for @soilAlluvial.
  ///
  /// In en, this message translates to:
  /// **'Alluvial'**
  String get soilAlluvial;

  /// No description provided for @soilLaterite.
  ///
  /// In en, this message translates to:
  /// **'Laterite'**
  String get soilLaterite;

  /// No description provided for @irrigationRainfed.
  ///
  /// In en, this message translates to:
  /// **'Rainfed'**
  String get irrigationRainfed;

  /// No description provided for @irrigationBorewell.
  ///
  /// In en, this message translates to:
  /// **'Borewell'**
  String get irrigationBorewell;

  /// No description provided for @irrigationCanal.
  ///
  /// In en, this message translates to:
  /// **'Canal'**
  String get irrigationCanal;

  /// No description provided for @irrigationTank.
  ///
  /// In en, this message translates to:
  /// **'Tank'**
  String get irrigationTank;

  /// No description provided for @irrigationOpenWell.
  ///
  /// In en, this message translates to:
  /// **'Open well'**
  String get irrigationOpenWell;

  /// No description provided for @irrigationDrip.
  ///
  /// In en, this message translates to:
  /// **'Drip'**
  String get irrigationDrip;

  /// No description provided for @irrigationSprinkler.
  ///
  /// In en, this message translates to:
  /// **'Sprinkler'**
  String get irrigationSprinkler;

  /// No description provided for @ownershipOwn.
  ///
  /// In en, this message translates to:
  /// **'Own'**
  String get ownershipOwn;

  /// No description provided for @ownershipLeased.
  ///
  /// In en, this message translates to:
  /// **'Leased'**
  String get ownershipLeased;

  /// No description provided for @seasonKharif.
  ///
  /// In en, this message translates to:
  /// **'Kharif'**
  String get seasonKharif;

  /// No description provided for @seasonRabi.
  ///
  /// In en, this message translates to:
  /// **'Rabi'**
  String get seasonRabi;

  /// No description provided for @seasonZaid.
  ///
  /// In en, this message translates to:
  /// **'Zaid (summer)'**
  String get seasonZaid;

  /// No description provided for @profileTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get profileTabOverview;

  /// No description provided for @profileTabVisits.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get profileTabVisits;

  /// No description provided for @profileTabDiagnoses.
  ///
  /// In en, this message translates to:
  /// **'Diagnoses'**
  String get profileTabDiagnoses;

  /// No description provided for @profileTabOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get profileTabOrders;

  /// No description provided for @profileTabKhata.
  ///
  /// In en, this message translates to:
  /// **'Khata'**
  String get profileTabKhata;

  /// No description provided for @profileStartVisit.
  ///
  /// In en, this message translates to:
  /// **'Start visit'**
  String get profileStartVisit;

  /// No description provided for @profileScout.
  ///
  /// In en, this message translates to:
  /// **'Scout'**
  String get profileScout;

  /// No description provided for @profileNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get profileNewOrder;

  /// No description provided for @profileCollect.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get profileCollect;

  /// No description provided for @profileComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming in a later update'**
  String get profileComingSoon;

  /// No description provided for @profileVisitsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No visits yet'**
  String get profileVisitsEmpty;

  /// No description provided for @profileDiagnosesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No diagnoses yet'**
  String get profileDiagnosesEmpty;

  /// No description provided for @profileOrdersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get profileOrdersEmpty;

  /// No description provided for @profileKhataEmpty.
  ///
  /// In en, this message translates to:
  /// **'No khata entries yet'**
  String get profileKhataEmpty;

  /// No description provided for @profilePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get profilePhone;

  /// No description provided for @profileLandmark.
  ///
  /// In en, this message translates to:
  /// **'Landmark'**
  String get profileLandmark;

  /// No description provided for @profileLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profileLanguage;

  /// No description provided for @profileOwnership.
  ///
  /// In en, this message translates to:
  /// **'Land'**
  String get profileOwnership;

  /// No description provided for @profileFarms.
  ///
  /// In en, this message translates to:
  /// **'Farms'**
  String get profileFarms;

  /// No description provided for @profileAcres.
  ///
  /// In en, this message translates to:
  /// **'{acres} acres'**
  String profileAcres(String acres);

  /// No description provided for @profileAddFarm.
  ///
  /// In en, this message translates to:
  /// **'Add farm'**
  String get profileAddFarm;

  /// No description provided for @profileEditFarm.
  ///
  /// In en, this message translates to:
  /// **'Edit farm'**
  String get profileEditFarm;

  /// No description provided for @profileFarmPlots.
  ///
  /// In en, this message translates to:
  /// **'{count} crops'**
  String profileFarmPlots(int count);

  /// No description provided for @profileNoFarms.
  ///
  /// In en, this message translates to:
  /// **'No farms yet'**
  String get profileNoFarms;

  /// No description provided for @profileDuplicateTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate — merge?'**
  String get profileDuplicateTitle;

  /// No description provided for @profileDuplicateBody.
  ///
  /// In en, this message translates to:
  /// **'The server already has a farmer with this number. Open the existing record and merge the details.'**
  String get profileDuplicateBody;

  /// No description provided for @profileRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync rejected'**
  String get profileRejectedTitle;

  /// No description provided for @profileRejectedHelp.
  ///
  /// In en, this message translates to:
  /// **'Open Sync details to fix and retry.'**
  String get profileRejectedHelp;

  /// No description provided for @profileNotFound.
  ///
  /// In en, this message translates to:
  /// **'Farmer not found'**
  String get profileNotFound;

  /// No description provided for @profileVerifyPhone.
  ///
  /// In en, this message translates to:
  /// **'Verify phone'**
  String get profileVerifyPhone;

  /// No description provided for @consentGiven.
  ///
  /// In en, this message translates to:
  /// **'Given'**
  String get consentGiven;

  /// No description provided for @consentNotGiven.
  ///
  /// In en, this message translates to:
  /// **'Not given'**
  String get consentNotGiven;

  /// No description provided for @farmEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit farm'**
  String get farmEditTitle;

  /// No description provided for @farmAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add farm'**
  String get farmAddTitle;

  /// No description provided for @mapNoBoundary.
  ///
  /// In en, this message translates to:
  /// **'No boundary yet'**
  String get mapNoBoundary;

  /// No description provided for @mapAttribution.
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap contributors'**
  String get mapAttribution;

  /// No description provided for @mapCurrentPosition.
  ///
  /// In en, this message translates to:
  /// **'Your position'**
  String get mapCurrentPosition;

  /// No description provided for @mapCorner.
  ///
  /// In en, this message translates to:
  /// **'Corner {index}'**
  String mapCorner(int index);

  /// No description provided for @mapFarmBoundary.
  ///
  /// In en, this message translates to:
  /// **'Farm boundary'**
  String get mapFarmBoundary;
}

class _CoreLocalizationsDelegate
    extends LocalizationsDelegate<CoreLocalizations> {
  const _CoreLocalizationsDelegate();

  @override
  Future<CoreLocalizations> load(Locale locale) {
    return SynchronousFuture<CoreLocalizations>(
      lookupCoreLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'kn', 'mr', 'te'].contains(locale.languageCode);

  @override
  bool shouldReload(_CoreLocalizationsDelegate old) => false;
}

CoreLocalizations lookupCoreLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return CoreLocalizationsEn();
    case 'hi':
      return CoreLocalizationsHi();
    case 'kn':
      return CoreLocalizationsKn();
    case 'mr':
      return CoreLocalizationsMr();
    case 'te':
      return CoreLocalizationsTe();
  }

  throw FlutterError(
    'CoreLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
