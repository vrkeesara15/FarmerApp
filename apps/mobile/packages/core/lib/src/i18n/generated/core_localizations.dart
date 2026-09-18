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

  /// Persistent Android notification title while on duty (FA-010)
  ///
  /// In en, this message translates to:
  /// **'On duty — location on'**
  String get dutyNotificationTitle;

  /// No description provided for @dutyChannelName.
  ///
  /// In en, this message translates to:
  /// **'Duty'**
  String get dutyChannelName;

  /// No description provided for @dutyAlertsChannelName.
  ///
  /// In en, this message translates to:
  /// **'Duty alerts'**
  String get dutyAlertsChannelName;

  /// No description provided for @dutyPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Still on duty?'**
  String get dutyPromptTitle;

  /// No description provided for @dutyPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Ending at {time}'**
  String dutyPromptBody(String time);

  /// No description provided for @dutyEndedTitle.
  ///
  /// In en, this message translates to:
  /// **'Duty ended'**
  String get dutyEndedTitle;

  /// No description provided for @dutyAutoEndedBody.
  ///
  /// In en, this message translates to:
  /// **'Your day ended automatically at {time}.'**
  String dutyAutoEndedBody(String time);

  /// No description provided for @dutyServerEndedBody.
  ///
  /// In en, this message translates to:
  /// **'Your duty was ended by the server (idle or end of day).'**
  String get dutyServerEndedBody;

  /// No description provided for @dutyAutoEndAt.
  ///
  /// In en, this message translates to:
  /// **'Ends automatically at {time}'**
  String dutyAutoEndAt(String time);

  /// No description provided for @dutyBlockedPolicy.
  ///
  /// In en, this message translates to:
  /// **'Accept the location policy to go on duty'**
  String get dutyBlockedPolicy;

  /// No description provided for @dutyReviewPolicy.
  ///
  /// In en, this message translates to:
  /// **'Review policy'**
  String get dutyReviewPolicy;

  /// No description provided for @dutyPointsPending.
  ///
  /// In en, this message translates to:
  /// **'{count} points waiting to upload'**
  String dutyPointsPending(int count);

  /// No description provided for @dutyNoticeAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'You are already on duty on another device. This one stays off.'**
  String get dutyNoticeAlreadyActive;

  /// No description provided for @dutyNoticePolicy.
  ///
  /// In en, this message translates to:
  /// **'Please accept the current location policy before going on duty.'**
  String get dutyNoticePolicy;

  /// No description provided for @dutyNoticeLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not get your location. Turn on location and try again.'**
  String get dutyNoticeLocationUnavailable;

  /// No description provided for @integrityBanner.
  ///
  /// In en, this message translates to:
  /// **'Some device checks reported issues; visits may be reviewed.'**
  String get integrityBanner;

  /// No description provided for @disclosureIntro.
  ///
  /// In en, this message translates to:
  /// **'Before you start, here is what Mitra records and why.'**
  String get disclosureIntro;

  /// No description provided for @disclosureVersion.
  ///
  /// In en, this message translates to:
  /// **'Policy version {version}'**
  String disclosureVersion(String version);

  /// No description provided for @disclosureUpdated.
  ///
  /// In en, this message translates to:
  /// **'The location policy has changed. Please read and accept the new version.'**
  String get disclosureUpdated;

  /// No description provided for @policySheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Location policy'**
  String get policySheetTitle;

  /// Full employee location policy (FA-011 / VV-010), version 2026-09-v1; English is the hashed source in design/copy/location_policy_en.md
  ///
  /// In en, this message translates to:
  /// **'Mitra location policy (version 2026-09-v1)\n\n1. What we collect. While you are on duty, Mitra records your location (latitude, longitude, accuracy, speed, direction), the time, your battery level and basic device checks (mock-location, rooted device, clock difference). It also records the photos, notes and farmer confirmations you capture during visits.\n\n2. Only while on duty. Location is recorded only after you switch duty on, and it stops the moment you switch duty off, when the day ends at the tenant’s set time (20:00 by default) or after 60 minutes idle at your home location. Nothing is recorded while you are off duty, and a notification is always visible while location is on.\n\n3. Why we collect it. Your track computes the kilometres for your travel allowance, and your location at a visit gives you credit for that visit. No track means no automatic travel allowance and no verified visit.\n\n4. Who can see it. Your cluster head, the directors and the owner of your organisation can see your track and visits for their area, and auditors can review flagged visits. Store managers and farmers never see your location. Raw points are kept for 180 days and then reduced to daily totals.'**
  String get locationPolicyText;

  /// No description provided for @permissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Permissions Mitra needs'**
  String get permissionsTitle;

  /// No description provided for @permissionsIntro.
  ///
  /// In en, this message translates to:
  /// **'Mitra asks for these one by one. You can change them later in Settings.'**
  String get permissionsIntro;

  /// No description provided for @permLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get permLocationTitle;

  /// No description provided for @permLocationBody.
  ///
  /// In en, this message translates to:
  /// **'To record your track while on duty and check you are at the farm.'**
  String get permLocationBody;

  /// No description provided for @permBackgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Location all the time'**
  String get permBackgroundTitle;

  /// No description provided for @permBackgroundBody.
  ///
  /// In en, this message translates to:
  /// **'Choose \"Allow all the time\" so tracking continues while the screen is off. It still runs only while you are on duty.'**
  String get permBackgroundBody;

  /// No description provided for @permCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get permCameraTitle;

  /// No description provided for @permCameraBody.
  ///
  /// In en, this message translates to:
  /// **'For farm and visit photos taken inside the app.'**
  String get permCameraBody;

  /// No description provided for @permNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get permNotificationsTitle;

  /// No description provided for @permNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'To show the on-duty notice and remind you before duty ends.'**
  String get permNotificationsBody;

  /// No description provided for @permGranted.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get permGranted;

  /// No description provided for @permDenied.
  ///
  /// In en, this message translates to:
  /// **'Not allowed'**
  String get permDenied;

  /// No description provided for @permOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get permOpenSettings;

  /// No description provided for @permAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get permAllow;

  /// No description provided for @registeredTitle.
  ///
  /// In en, this message translates to:
  /// **'Device registered'**
  String get registeredTitle;

  /// No description provided for @registeredBody.
  ///
  /// In en, this message translates to:
  /// **'You are set. Go on duty from Home to start your day.'**
  String get registeredBody;

  /// No description provided for @registeredStart.
  ///
  /// In en, this message translates to:
  /// **'Go to Home'**
  String get registeredStart;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @homeTodayStats.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get homeTodayStats;

  /// No description provided for @statVisitsVerified.
  ///
  /// In en, this message translates to:
  /// **'Visits verified'**
  String get statVisitsVerified;

  /// No description provided for @statFarmersAdded.
  ///
  /// In en, this message translates to:
  /// **'Farmers added'**
  String get statFarmersAdded;

  /// No description provided for @statCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get statCollections;

  /// No description provided for @homeNextUp.
  ///
  /// In en, this message translates to:
  /// **'Next up'**
  String get homeNextUp;

  /// No description provided for @homeNextUpEmpty.
  ///
  /// In en, this message translates to:
  /// **'No beat plan yet'**
  String get homeNextUpEmpty;

  /// No description provided for @homeNextUpEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Your cluster head will assign villages. Until then, add farmers and start visits.'**
  String get homeNextUpEmptyHelp;

  /// No description provided for @homeQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get homeQuickActions;

  /// No description provided for @actionStartVisit.
  ///
  /// In en, this message translates to:
  /// **'Start visit'**
  String get actionStartVisit;

  /// No description provided for @actionScoutCrop.
  ///
  /// In en, this message translates to:
  /// **'Scout crop'**
  String get actionScoutCrop;

  /// No description provided for @actionCollectPayment.
  ///
  /// In en, this message translates to:
  /// **'Collect payment'**
  String get actionCollectPayment;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navFarmers.
  ///
  /// In en, this message translates to:
  /// **'Farmers'**
  String get navFarmers;

  /// No description provided for @navVisits.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get navVisits;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @navMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get navMe;

  /// No description provided for @myDayTitle.
  ///
  /// In en, this message translates to:
  /// **'My day'**
  String get myDayTitle;

  /// No description provided for @myDayKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km today'**
  String myDayKm(String km);

  /// No description provided for @myDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No duty today yet'**
  String get myDayEmpty;

  /// No description provided for @myDayEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Go on duty from Home; your track and km appear here.'**
  String get myDayEmptyHelp;

  /// No description provided for @myDaySession.
  ///
  /// In en, this message translates to:
  /// **'Duty {start} – {end}'**
  String myDaySession(String start, String end);

  /// No description provided for @myDaySessionActive.
  ///
  /// In en, this message translates to:
  /// **'Duty since {start}'**
  String myDaySessionActive(String start);

  /// No description provided for @myDayPoints.
  ///
  /// In en, this message translates to:
  /// **'{pending} pending · {accepted} accepted'**
  String myDayPoints(int pending, int accepted);

  /// No description provided for @myDayGapsTitle.
  ///
  /// In en, this message translates to:
  /// **'Gaps and reasons'**
  String get myDayGapsTitle;

  /// No description provided for @myDayGapsHelp.
  ///
  /// In en, this message translates to:
  /// **'Gap reasons arrive with the next update.'**
  String get myDayGapsHelp;

  /// No description provided for @myDayEndReasonManual.
  ///
  /// In en, this message translates to:
  /// **'Ended by you'**
  String get myDayEndReasonManual;

  /// No description provided for @myDayEndReasonAutoTime.
  ///
  /// In en, this message translates to:
  /// **'Ended at day end'**
  String get myDayEndReasonAutoTime;

  /// No description provided for @myDayEndReasonAutoIdle.
  ///
  /// In en, this message translates to:
  /// **'Ended after idle'**
  String get myDayEndReasonAutoIdle;

  /// No description provided for @myDayEndReasonForced.
  ///
  /// In en, this message translates to:
  /// **'Ended by manager'**
  String get myDayEndReasonForced;

  /// No description provided for @myDayEndReasonRejected.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get myDayEndReasonRejected;

  /// No description provided for @syncEntityDutySession.
  ///
  /// In en, this message translates to:
  /// **'Duty session'**
  String get syncEntityDutySession;

  /// No description provided for @syncEntityLocationBatch.
  ///
  /// In en, this message translates to:
  /// **'Location points'**
  String get syncEntityLocationBatch;

  /// No description provided for @syncEntityPolicyAcceptance.
  ///
  /// In en, this message translates to:
  /// **'Policy acceptance'**
  String get syncEntityPolicyAcceptance;

  /// No description provided for @visitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get visitsTitle;

  /// No description provided for @visitsTabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get visitsTabToday;

  /// No description provided for @visitsTabWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get visitsTabWeek;

  /// No description provided for @visitsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get visitsFilterAll;

  /// No description provided for @visitsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No visits yet'**
  String get visitsEmptyTitle;

  /// No description provided for @visitsEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Start a visit from a farmer profile or with the button below.'**
  String get visitsEmptyHelp;

  /// No description provided for @visitStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get visitStatusOpen;

  /// No description provided for @visitCardPending.
  ///
  /// In en, this message translates to:
  /// **'Will sync when online'**
  String get visitCardPending;

  /// No description provided for @visitCardFailed.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get visitCardFailed;

  /// No description provided for @visitChooseFarmer.
  ///
  /// In en, this message translates to:
  /// **'Choose a farmer'**
  String get visitChooseFarmer;

  /// No description provided for @visitFarmLabel.
  ///
  /// In en, this message translates to:
  /// **'Farm'**
  String get visitFarmLabel;

  /// No description provided for @visitFarmNoBoundary.
  ///
  /// In en, this message translates to:
  /// **'No boundary recorded for this farm'**
  String get visitFarmNoBoundary;

  /// No description provided for @visitPurposeLabel.
  ///
  /// In en, this message translates to:
  /// **'Purpose'**
  String get visitPurposeLabel;

  /// No description provided for @visitOffDutyTitle.
  ///
  /// In en, this message translates to:
  /// **'Go on duty first'**
  String get visitOffDutyTitle;

  /// No description provided for @visitOffDutyBody.
  ///
  /// In en, this message translates to:
  /// **'Visits are recorded only while you are on duty. Switch duty on from Home and come back.'**
  String get visitOffDutyBody;

  /// No description provided for @visitGoHome.
  ///
  /// In en, this message translates to:
  /// **'Go to Home'**
  String get visitGoHome;

  /// No description provided for @visitLocating.
  ///
  /// In en, this message translates to:
  /// **'Getting your location…'**
  String get visitLocating;

  /// No description provided for @visitNoFix.
  ///
  /// In en, this message translates to:
  /// **'Could not get your location. Move under open sky and try again.'**
  String get visitNoFix;

  /// No description provided for @visitRefreshLocation.
  ///
  /// In en, this message translates to:
  /// **'Check location again'**
  String get visitRefreshLocation;

  /// No description provided for @visitAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy ±{metres} m'**
  String visitAccuracy(int metres);

  /// No description provided for @visitInsideGeofence.
  ///
  /// In en, this message translates to:
  /// **'You are inside the farm geofence'**
  String get visitInsideGeofence;

  /// No description provided for @visitAtMeetingPoint.
  ///
  /// In en, this message translates to:
  /// **'You are at the village meeting point'**
  String get visitAtMeetingPoint;

  /// No description provided for @visitOutsideFarm.
  ///
  /// In en, this message translates to:
  /// **'{distance} m from the farm boundary; the geofence is {radius} m.'**
  String visitOutsideFarm(int distance, int radius);

  /// No description provided for @visitOutsideMeeting.
  ///
  /// In en, this message translates to:
  /// **'{distance} m from the meeting point; the allowed radius is {radius} m.'**
  String visitOutsideMeeting(int distance, int radius);

  /// No description provided for @visitNoTarget.
  ///
  /// In en, this message translates to:
  /// **'This farm has no boundary and the village has no meeting point. Check in with an override note.'**
  String get visitNoTarget;

  /// No description provided for @visitRequestOverride.
  ///
  /// In en, this message translates to:
  /// **'Request override'**
  String get visitRequestOverride;

  /// No description provided for @visitOverrideNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Why are you checking in from here?'**
  String get visitOverrideNoteLabel;

  /// No description provided for @visitOverrideNoteHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Met the farmer at the market'**
  String get visitOverrideNoteHint;

  /// No description provided for @visitOverrideNoteRequired.
  ///
  /// In en, this message translates to:
  /// **'Add a note to request an override'**
  String get visitOverrideNoteRequired;

  /// No description provided for @visitOverrideHelp.
  ///
  /// In en, this message translates to:
  /// **'Your cluster head reviews the override. The visit earns geofence credit only if it is approved.'**
  String get visitOverrideHelp;

  /// No description provided for @visitCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get visitCheckIn;

  /// No description provided for @visitCheckInOverride.
  ///
  /// In en, this message translates to:
  /// **'Check in with override'**
  String get visitCheckInOverride;

  /// No description provided for @visitInProgress.
  ///
  /// In en, this message translates to:
  /// **'Visit in progress'**
  String get visitInProgress;

  /// No description provided for @visitTimerLabel.
  ///
  /// In en, this message translates to:
  /// **'Time on visit'**
  String get visitTimerLabel;

  /// No description provided for @visitMinDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum {minutes} min'**
  String visitMinDuration(int minutes);

  /// No description provided for @visitDurationNeeds.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min of {minimum} min'**
  String visitDurationNeeds(int minutes, int minimum);

  /// No description provided for @visitUnderMinimum.
  ///
  /// In en, this message translates to:
  /// **'Under the minimum of {minutes} min. The visit is flagged, not rejected.'**
  String visitUnderMinimum(int minutes);

  /// No description provided for @visitPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get visitPhotos;

  /// No description provided for @visitTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get visitTakePhoto;

  /// No description provided for @visitPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String visitPhotoCount(int count);

  /// No description provided for @visitPhotosHelp.
  ///
  /// In en, this message translates to:
  /// **'In-app camera only. Take at least one photo at the farm.'**
  String get visitPhotosHelp;

  /// No description provided for @visitNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get visitNotesLabel;

  /// No description provided for @visitNotesHint.
  ///
  /// In en, this message translates to:
  /// **'What did you observe or advise?'**
  String get visitNotesHint;

  /// No description provided for @visitVoiceInputSoon.
  ///
  /// In en, this message translates to:
  /// **'Voice input arrives in a later update'**
  String get visitVoiceInputSoon;

  /// No description provided for @visitCropStageLabel.
  ///
  /// In en, this message translates to:
  /// **'Crop stage'**
  String get visitCropStageLabel;

  /// No description provided for @cropStageSown.
  ///
  /// In en, this message translates to:
  /// **'Sown'**
  String get cropStageSown;

  /// No description provided for @cropStageMaturity.
  ///
  /// In en, this message translates to:
  /// **'Maturity'**
  String get cropStageMaturity;

  /// No description provided for @cropStageHarvested.
  ///
  /// In en, this message translates to:
  /// **'Harvested'**
  String get cropStageHarvested;

  /// No description provided for @visitProofTitle.
  ///
  /// In en, this message translates to:
  /// **'Proof of visit'**
  String get visitProofTitle;

  /// No description provided for @visitExpectedScore.
  ///
  /// In en, this message translates to:
  /// **'Expected score'**
  String get visitExpectedScore;

  /// No description provided for @visitServerScore.
  ///
  /// In en, this message translates to:
  /// **'Score from the server'**
  String get visitServerScore;

  /// No description provided for @visitConfirmFarmer.
  ///
  /// In en, this message translates to:
  /// **'Farmer confirmation'**
  String get visitConfirmFarmer;

  /// No description provided for @visitCheckOut.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get visitCheckOut;

  /// No description provided for @visitCheckInPending.
  ///
  /// In en, this message translates to:
  /// **'Check-in will sync when online'**
  String get visitCheckInPending;

  /// No description provided for @visitCheckInSynced.
  ///
  /// In en, this message translates to:
  /// **'Check-in synced'**
  String get visitCheckInSynced;

  /// No description provided for @visitRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Check-in refused'**
  String get visitRejectedTitle;

  /// No description provided for @visitRejectedOutside.
  ///
  /// In en, this message translates to:
  /// **'The server placed you {distance} m outside the geofence.'**
  String visitRejectedOutside(int distance);

  /// No description provided for @visitRejectedNoTarget.
  ///
  /// In en, this message translates to:
  /// **'The server found nothing to check your location against.'**
  String get visitRejectedNoTarget;

  /// No description provided for @visitRetryFromFarm.
  ///
  /// In en, this message translates to:
  /// **'Retry from the farm'**
  String get visitRetryFromFarm;

  /// No description provided for @visitRetryStillOutside.
  ///
  /// In en, this message translates to:
  /// **'Still {distance} m outside. Move closer or request an override.'**
  String visitRetryStillOutside(int distance);

  /// No description provided for @visitRetryQueued.
  ///
  /// In en, this message translates to:
  /// **'Check-in queued again with your current location.'**
  String get visitRetryQueued;

  /// No description provided for @proofGeofenceOverride.
  ///
  /// In en, this message translates to:
  /// **'Override requested; waiting for the cluster head'**
  String get proofGeofenceOverride;

  /// No description provided for @proofGeofenceOutside.
  ///
  /// In en, this message translates to:
  /// **'Outside the geofence'**
  String get proofGeofenceOutside;

  /// No description provided for @proofPhotoDone.
  ///
  /// In en, this message translates to:
  /// **'Photo with location taken'**
  String get proofPhotoDone;

  /// No description provided for @proofDurationDone.
  ///
  /// In en, this message translates to:
  /// **'Minimum duration reached'**
  String get proofDurationDone;

  /// No description provided for @proofIntegrityIssue.
  ///
  /// In en, this message translates to:
  /// **'Device checks reported issues; this part scores 0'**
  String get proofIntegrityIssue;

  /// No description provided for @visitConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Farmer confirmation'**
  String get visitConfirmTitle;

  /// No description provided for @visitConfirmIntro.
  ///
  /// In en, this message translates to:
  /// **'Ask the farmer to confirm this visit in one of these ways.'**
  String get visitConfirmIntro;

  /// No description provided for @visitConfirmOtp.
  ///
  /// In en, this message translates to:
  /// **'OTP by SMS'**
  String get visitConfirmOtp;

  /// No description provided for @visitConfirmOtpHelp.
  ///
  /// In en, this message translates to:
  /// **'A code goes to the farmer’s phone; type it here.'**
  String get visitConfirmOtpHelp;

  /// No description provided for @visitConfirmPush.
  ///
  /// In en, this message translates to:
  /// **'Ask in Kisan app'**
  String get visitConfirmPush;

  /// No description provided for @visitConfirmPushHelp.
  ///
  /// In en, this message translates to:
  /// **'The farmer taps Confirm in their app.'**
  String get visitConfirmPushHelp;

  /// No description provided for @visitConfirmQr.
  ///
  /// In en, this message translates to:
  /// **'Show QR'**
  String get visitConfirmQr;

  /// No description provided for @visitConfirmQrHelp.
  ///
  /// In en, this message translates to:
  /// **'The farmer scans this with the Kisan app.'**
  String get visitConfirmQrHelp;

  /// No description provided for @visitConfirmNeedsNetwork.
  ///
  /// In en, this message translates to:
  /// **'This needs network. Try again when you are online.'**
  String get visitConfirmNeedsNetwork;

  /// No description provided for @visitConfirmQrNeedsSync.
  ///
  /// In en, this message translates to:
  /// **'The QR needs one sync first. Connect once and come back.'**
  String get visitConfirmQrNeedsSync;

  /// No description provided for @visitConfirmNotSynced.
  ///
  /// In en, this message translates to:
  /// **'The check-in has not reached the server yet. Sync and try again.'**
  String get visitConfirmNotSynced;

  /// No description provided for @visitConfirmQueued.
  ///
  /// In en, this message translates to:
  /// **'Request saved. It goes to the farmer’s app as soon as you are online.'**
  String get visitConfirmQueued;

  /// No description provided for @visitConfirmWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the farmer…'**
  String get visitConfirmWaiting;

  /// No description provided for @visitConfirmWaitingPush.
  ///
  /// In en, this message translates to:
  /// **'We asked the farmer in the Kisan app. This screen updates when they confirm.'**
  String get visitConfirmWaitingPush;

  /// No description provided for @visitConfirmQrWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the farmer to scan…'**
  String get visitConfirmQrWaiting;

  /// No description provided for @visitConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Farmer confirmed'**
  String get visitConfirmed;

  /// No description provided for @visitConfirmedVia.
  ///
  /// In en, this message translates to:
  /// **'Confirmed via {channel}'**
  String visitConfirmedVia(String channel);

  /// No description provided for @visitConfirmOtpSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {phone}'**
  String visitConfirmOtpSent(String phone);

  /// No description provided for @visitConfirmAlready.
  ///
  /// In en, this message translates to:
  /// **'This visit is already confirmed.'**
  String get visitConfirmAlready;

  /// No description provided for @visitConfirmRefused.
  ///
  /// In en, this message translates to:
  /// **'The farmer cannot be asked this way right now. Try another option.'**
  String get visitConfirmRefused;

  /// No description provided for @visitConfirmContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue to check-out'**
  String get visitConfirmContinue;

  /// No description provided for @visitConfirmLater.
  ///
  /// In en, this message translates to:
  /// **'Confirm later'**
  String get visitConfirmLater;

  /// No description provided for @visitConfirmExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires in {minutes} min'**
  String visitConfirmExpires(int minutes);

  /// No description provided for @visitConfirmChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another way'**
  String get visitConfirmChooseAnother;

  /// No description provided for @visitSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Check-out summary'**
  String get visitSummaryTitle;

  /// No description provided for @visitSummaryDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get visitSummaryDuration;

  /// No description provided for @visitSummaryMissing.
  ///
  /// In en, this message translates to:
  /// **'What was missing'**
  String get visitSummaryMissing;

  /// No description provided for @visitSummaryComplete.
  ///
  /// In en, this message translates to:
  /// **'Everything is in place'**
  String get visitSummaryComplete;

  /// No description provided for @visitSummaryPending.
  ///
  /// In en, this message translates to:
  /// **'The server confirms the score after the next sync'**
  String get visitSummaryPending;

  /// No description provided for @visitSummaryServer.
  ///
  /// In en, this message translates to:
  /// **'Score confirmed by the server'**
  String get visitSummaryServer;

  /// No description provided for @visitSummaryNotCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'This visit is still open.'**
  String get visitSummaryNotCheckedOut;

  /// No description provided for @visitSummaryOverridePending.
  ///
  /// In en, this message translates to:
  /// **'Override waiting for review'**
  String get visitSummaryOverridePending;

  /// No description provided for @visitDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get visitDone;

  /// No description provided for @syncEntityVisit.
  ///
  /// In en, this message translates to:
  /// **'Visit'**
  String get syncEntityVisit;

  /// No description provided for @syncEntityVisitPhoto.
  ///
  /// In en, this message translates to:
  /// **'Visit photo'**
  String get syncEntityVisitPhoto;

  /// No description provided for @syncEntityVisitConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Farmer confirmation'**
  String get syncEntityVisitConfirmation;

  /// No description provided for @catalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get catalogTitle;

  /// No description provided for @catalogForFarmer.
  ///
  /// In en, this message translates to:
  /// **'For {name}'**
  String catalogForFarmer(String name);

  /// No description provided for @catalogSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name, brand or ingredient'**
  String get catalogSearchHint;

  /// No description provided for @catalogCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get catalogCategoryAll;

  /// No description provided for @catalogCategorySeed.
  ///
  /// In en, this message translates to:
  /// **'Seeds'**
  String get catalogCategorySeed;

  /// No description provided for @catalogCategoryFertiliser.
  ///
  /// In en, this message translates to:
  /// **'Fertilisers'**
  String get catalogCategoryFertiliser;

  /// No description provided for @catalogCategoryPesticide.
  ///
  /// In en, this message translates to:
  /// **'Pesticides'**
  String get catalogCategoryPesticide;

  /// No description provided for @catalogCategoryFungicide.
  ///
  /// In en, this message translates to:
  /// **'Fungicides'**
  String get catalogCategoryFungicide;

  /// No description provided for @catalogCategoryHerbicide.
  ///
  /// In en, this message translates to:
  /// **'Herbicides'**
  String get catalogCategoryHerbicide;

  /// No description provided for @catalogCategoryGrowth.
  ///
  /// In en, this message translates to:
  /// **'Growth promoters'**
  String get catalogCategoryGrowth;

  /// No description provided for @catalogCategoryTool.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get catalogCategoryTool;

  /// No description provided for @catalogCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catalogCategoryOther;

  /// No description provided for @catalogAsOf.
  ///
  /// In en, this message translates to:
  /// **'Prices and stock as of {time}'**
  String catalogAsOf(String time);

  /// No description provided for @catalogStale.
  ///
  /// In en, this message translates to:
  /// **'Prices and stock may be out of date (as of {time}). Refresh when online.'**
  String catalogStale(String time);

  /// No description provided for @catalogNeverLoaded.
  ///
  /// In en, this message translates to:
  /// **'The catalogue is not on this phone yet'**
  String get catalogNeverLoaded;

  /// No description provided for @catalogNeverLoadedHelp.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to download products and prices.'**
  String get catalogNeverLoadedHelp;

  /// No description provided for @catalogRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get catalogRefresh;

  /// No description provided for @catalogRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh. Showing saved products.'**
  String get catalogRefreshFailed;

  /// No description provided for @catalogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No products match'**
  String get catalogEmpty;

  /// No description provided for @catalogEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Try another name or category.'**
  String get catalogEmptyHelp;

  /// No description provided for @catalogStoreUnknown.
  ///
  /// In en, this message translates to:
  /// **'Store not known yet. Stock shows after the next sync.'**
  String get catalogStoreUnknown;

  /// No description provided for @productPriceEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated price'**
  String get productPriceEstimate;

  /// No description provided for @productStockNearest.
  ///
  /// In en, this message translates to:
  /// **'{count} in stock at the nearest store'**
  String productStockNearest(int count);

  /// No description provided for @productStockAsOf.
  ///
  /// In en, this message translates to:
  /// **'as of {time}'**
  String productStockAsOf(String time);

  /// No description provided for @productInCart.
  ///
  /// In en, this message translates to:
  /// **'{count} in cart'**
  String productInCart(int count);

  /// No description provided for @cartEstimatedTotal.
  ///
  /// In en, this message translates to:
  /// **'Estimated total'**
  String get cartEstimatedTotal;

  /// No description provided for @cartViewCart.
  ///
  /// In en, this message translates to:
  /// **'View cart'**
  String get cartViewCart;

  /// No description provided for @cartTitle.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get cartTitle;

  /// No description provided for @cartEmpty.
  ///
  /// In en, this message translates to:
  /// **'The cart is empty'**
  String get cartEmpty;

  /// No description provided for @cartEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Add products from the catalogue.'**
  String get cartEmptyHelp;

  /// No description provided for @cartAddMore.
  ///
  /// In en, this message translates to:
  /// **'Add more products'**
  String get cartAddMore;

  /// No description provided for @cartSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal (estimate)'**
  String get cartSubtotal;

  /// No description provided for @cartTax.
  ///
  /// In en, this message translates to:
  /// **'GST (estimate)'**
  String get cartTax;

  /// No description provided for @cartEstimateNote.
  ///
  /// In en, this message translates to:
  /// **'Prices are estimates from the saved price list. The store confirms the final amount when the order syncs.'**
  String get cartEstimateNote;

  /// No description provided for @cartFulfilment.
  ///
  /// In en, this message translates to:
  /// **'How will the farmer get it?'**
  String get cartFulfilment;

  /// No description provided for @fulfilmentPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup at store'**
  String get fulfilmentPickup;

  /// No description provided for @fulfilmentDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get fulfilmentDelivery;

  /// No description provided for @cartChoosePayment.
  ///
  /// In en, this message translates to:
  /// **'Choose payment'**
  String get cartChoosePayment;

  /// No description provided for @cartDecrease.
  ///
  /// In en, this message translates to:
  /// **'Remove one'**
  String get cartDecrease;

  /// No description provided for @cartIncrease.
  ///
  /// In en, this message translates to:
  /// **'Add one'**
  String get cartIncrease;

  /// No description provided for @cartShortLine.
  ///
  /// In en, this message translates to:
  /// **'Only {available} available at the store (asked {requested}).'**
  String cartShortLine(String available, String requested);

  /// No description provided for @cartUseAvailable.
  ///
  /// In en, this message translates to:
  /// **'Use {available}'**
  String cartUseAvailable(String available);

  /// No description provided for @cartShortTitle.
  ///
  /// In en, this message translates to:
  /// **'Some items are short at the store. Change the quantities and send again.'**
  String get cartShortTitle;

  /// No description provided for @checkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get checkoutTitle;

  /// No description provided for @checkoutOrderAmount.
  ///
  /// In en, this message translates to:
  /// **'Order total (estimate)'**
  String get checkoutOrderAmount;

  /// No description provided for @checkoutDuesAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount to collect (₹)'**
  String get checkoutDuesAmount;

  /// No description provided for @checkoutDuesBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance due {amount}'**
  String checkoutDuesBalance(String amount);

  /// No description provided for @checkoutDuesTooMuch.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount up to {amount}'**
  String checkoutDuesTooMuch(String amount);

  /// No description provided for @checkoutDuesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get checkoutDuesInvalid;

  /// No description provided for @checkoutPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place order'**
  String get checkoutPlaceOrder;

  /// No description provided for @checkoutCollect.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get checkoutCollect;

  /// No description provided for @checkoutNeedsInternet.
  ///
  /// In en, this message translates to:
  /// **'Needs internet: use cash or credit'**
  String get checkoutNeedsInternet;

  /// No description provided for @checkoutCreditOrdersOnly.
  ///
  /// In en, this message translates to:
  /// **'Credit is only for orders'**
  String get checkoutCreditOrdersOnly;

  /// No description provided for @checkoutCreditLeft.
  ///
  /// In en, this message translates to:
  /// **'Limit left {amount}'**
  String checkoutCreditLeft(String amount);

  /// No description provided for @checkoutOfflineNote.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Cash and credit are saved on the phone and sent when online.'**
  String get checkoutOfflineNote;

  /// No description provided for @checkoutOrderNotSynced.
  ///
  /// In en, this message translates to:
  /// **'The order has not reached the server yet. Try again when online, or collect cash.'**
  String get checkoutOrderNotSynced;

  /// No description provided for @checkoutNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check the internet and try again.'**
  String get checkoutNetworkError;

  /// No description provided for @checkoutAlreadyPaid.
  ///
  /// In en, this message translates to:
  /// **'This order is already paid.'**
  String get checkoutAlreadyPaid;

  /// No description provided for @checkoutAmountMismatch.
  ///
  /// In en, this message translates to:
  /// **'The amount changed on the server. Check the order and try again.'**
  String get checkoutAmountMismatch;

  /// No description provided for @checkoutNothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due for this farmer.'**
  String get checkoutNothingDue;

  /// No description provided for @checkoutRefused.
  ///
  /// In en, this message translates to:
  /// **'The payment could not be created ({code}).'**
  String checkoutRefused(String code);

  /// No description provided for @paymentCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentCard;

  /// No description provided for @paymentDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get paymentDone;

  /// No description provided for @upiTitle.
  ///
  /// In en, this message translates to:
  /// **'UPI QR'**
  String get upiTitle;

  /// No description provided for @upiExpired.
  ///
  /// In en, this message translates to:
  /// **'QR expired'**
  String get upiExpired;

  /// No description provided for @upiCollectCash.
  ///
  /// In en, this message translates to:
  /// **'Collect cash instead'**
  String get upiCollectCash;

  /// No description provided for @linkTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment link'**
  String get linkTitle;

  /// No description provided for @linkSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment link sent'**
  String get linkSentTitle;

  /// No description provided for @linkSentVia.
  ///
  /// In en, this message translates to:
  /// **'Sent by {channel}. Ask the farmer to open the link and pay.'**
  String linkSentVia(String channel);

  /// No description provided for @channelSms.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get channelSms;

  /// No description provided for @channelWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get channelWhatsapp;

  /// No description provided for @linkResend.
  ///
  /// In en, this message translates to:
  /// **'Resend the link'**
  String get linkResend;

  /// No description provided for @linkResent.
  ///
  /// In en, this message translates to:
  /// **'Link sent again'**
  String get linkResent;

  /// No description provided for @linkCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Check payment'**
  String get linkCheckStatus;

  /// No description provided for @linkValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until {time}'**
  String linkValidUntil(String time);

  /// No description provided for @cashTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash receipt'**
  String get cashTitle;

  /// No description provided for @cashAmount.
  ///
  /// In en, this message translates to:
  /// **'Cash collected'**
  String get cashAmount;

  /// No description provided for @cashTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take receipt photo'**
  String get cashTakePhoto;

  /// No description provided for @cashRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get cashRetake;

  /// No description provided for @cashSave.
  ///
  /// In en, this message translates to:
  /// **'Save cash payment'**
  String get cashSave;

  /// No description provided for @cashPhotoHelp.
  ///
  /// In en, this message translates to:
  /// **'Photograph the receipt you gave the farmer. Only the in-app camera can be used.'**
  String get cashPhotoHelp;

  /// No description provided for @cashPhotoBad.
  ///
  /// In en, this message translates to:
  /// **'The photo is blurry or dark. Retake it in good light.'**
  String get cashPhotoBad;

  /// No description provided for @cashSaved.
  ///
  /// In en, this message translates to:
  /// **'Cash saved. Pending store reconciliation.'**
  String get cashSaved;

  /// No description provided for @cashPendingReconciliation.
  ///
  /// In en, this message translates to:
  /// **'Pending store reconciliation: the store checks the cash at day close.'**
  String get cashPendingReconciliation;

  /// No description provided for @creditTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit sale'**
  String get creditTitle;

  /// No description provided for @creditQueued.
  ///
  /// In en, this message translates to:
  /// **'Saved on the phone. The credit limit is checked when the phone is online.'**
  String get creditQueued;

  /// No description provided for @creditApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Added to the farmer’s khata'**
  String get creditApprovedTitle;

  /// No description provided for @creditNeedsApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Approval needed'**
  String get creditNeedsApprovalTitle;

  /// No description provided for @creditNeedsApprovalBody.
  ///
  /// In en, this message translates to:
  /// **'This sale is over the farmer’s credit limit. It was sent to the cluster head for approval.'**
  String get creditNeedsApprovalBody;

  /// No description provided for @creditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get creditLimit;

  /// No description provided for @creditBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance due now'**
  String get creditBalance;

  /// No description provided for @creditShortfall.
  ///
  /// In en, this message translates to:
  /// **'Over the limit by'**
  String get creditShortfall;

  /// No description provided for @creditSentToClusterHead.
  ///
  /// In en, this message translates to:
  /// **'Sent to cluster head'**
  String get creditSentToClusterHead;

  /// No description provided for @creditCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check approval'**
  String get creditCheckAgain;

  /// No description provided for @creditStillPending.
  ///
  /// In en, this message translates to:
  /// **'Not approved yet. Try again later.'**
  String get creditStillPending;

  /// No description provided for @creditOfflineCheck.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to check the approval.'**
  String get creditOfflineCheck;

  /// No description provided for @creditUseCash.
  ///
  /// In en, this message translates to:
  /// **'Collect cash instead'**
  String get creditUseCash;

  /// No description provided for @orderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get orderTitle;

  /// No description provided for @orderPlacedTitle.
  ///
  /// In en, this message translates to:
  /// **'Order placed'**
  String get orderPlacedTitle;

  /// No description provided for @orderQueuedTitle.
  ///
  /// In en, this message translates to:
  /// **'Order saved, waiting to sync'**
  String get orderQueuedTitle;

  /// No description provided for @orderQueuedHelp.
  ///
  /// In en, this message translates to:
  /// **'It goes to the store as soon as the phone is online.'**
  String get orderQueuedHelp;

  /// No description provided for @orderRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'The store could not take this order'**
  String get orderRejectedTitle;

  /// No description provided for @orderInsufficientStock.
  ///
  /// In en, this message translates to:
  /// **'Some items are short at the store:'**
  String get orderInsufficientStock;

  /// No description provided for @orderShortLine.
  ///
  /// In en, this message translates to:
  /// **'{product}: {available} available, {requested} asked'**
  String orderShortLine(String product, String available, String requested);

  /// No description provided for @orderSkuNotRecommendable.
  ///
  /// In en, this message translates to:
  /// **'A product is not approved for this crop and pest (label claim). Remove it and send again.'**
  String get orderSkuNotRecommendable;

  /// No description provided for @orderEditAndResend.
  ///
  /// In en, this message translates to:
  /// **'Edit and send again'**
  String get orderEditAndResend;

  /// No description provided for @orderSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get orderSummary;

  /// No description provided for @orderSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get orderSubtotal;

  /// No description provided for @orderTax.
  ///
  /// In en, this message translates to:
  /// **'GST'**
  String get orderTax;

  /// No description provided for @orderTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get orderTotal;

  /// No description provided for @orderTotalEstimate.
  ///
  /// In en, this message translates to:
  /// **'Total (estimate)'**
  String get orderTotalEstimate;

  /// No description provided for @orderStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get orderStatusTitle;

  /// No description provided for @orderStatusPlaced.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get orderStatusPlaced;

  /// No description provided for @orderStatusReserved.
  ///
  /// In en, this message translates to:
  /// **'Stock reserved'**
  String get orderStatusReserved;

  /// No description provided for @orderStatusPacked.
  ///
  /// In en, this message translates to:
  /// **'Packed'**
  String get orderStatusPacked;

  /// No description provided for @orderStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get orderStatusReady;

  /// No description provided for @orderStatusHandedOver.
  ///
  /// In en, this message translates to:
  /// **'Handed over'**
  String get orderStatusHandedOver;

  /// No description provided for @orderStatusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get orderStatusDelivered;

  /// No description provided for @orderStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get orderStatusCancelled;

  /// No description provided for @orderPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get orderPayments;

  /// No description provided for @orderNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payment yet'**
  String get orderNoPayments;

  /// No description provided for @orderShareInvoice.
  ///
  /// In en, this message translates to:
  /// **'Share invoice on WhatsApp'**
  String get orderShareInvoice;

  /// No description provided for @orderShareOffline.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to share the invoice.'**
  String get orderShareOffline;

  /// No description provided for @orderShareNoInvoice.
  ///
  /// In en, this message translates to:
  /// **'The invoice is issued when the store hands over the order.'**
  String get orderShareNoInvoice;

  /// No description provided for @orderShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not get the invoice link. Try again.'**
  String get orderShareFailed;

  /// No description provided for @orderShareText.
  ///
  /// In en, this message translates to:
  /// **'Invoice {number}: {url}'**
  String orderShareText(String number, String url);

  /// No description provided for @orderInvoiceNo.
  ///
  /// In en, this message translates to:
  /// **'Invoice {number}'**
  String orderInvoiceNo(String number);

  /// No description provided for @orderCollectPayment.
  ///
  /// In en, this message translates to:
  /// **'Collect payment'**
  String get orderCollectPayment;

  /// No description provided for @orderPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get orderPendingSync;

  /// No description provided for @orderRejected.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get orderRejected;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ordersTitle;

  /// No description provided for @ordersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get ordersEmpty;

  /// No description provided for @ordersEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Orders you place for farmers show here.'**
  String get ordersEmptyHelp;

  /// No description provided for @ordersNew.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get ordersNew;

  /// No description provided for @ordersCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get ordersCollections;

  /// No description provided for @ordersPickFarmer.
  ///
  /// In en, this message translates to:
  /// **'Choose a farmer'**
  String get ordersPickFarmer;

  /// No description provided for @khataTitle.
  ///
  /// In en, this message translates to:
  /// **'Khata'**
  String get khataTitle;

  /// No description provided for @khataAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of {time}'**
  String khataAsOf(String time);

  /// No description provided for @khataOfflineAsOf.
  ///
  /// In en, this message translates to:
  /// **'Offline: showing the khata saved at {time}'**
  String khataOfflineAsOf(String time);

  /// No description provided for @khataNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Khata not on this phone yet'**
  String get khataNotLoaded;

  /// No description provided for @khataNotLoadedHelp.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to load the farmer’s khata.'**
  String get khataNotLoadedHelp;

  /// No description provided for @khataOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue {amount}'**
  String khataOverdue(String amount);

  /// No description provided for @khataBucket0to30.
  ///
  /// In en, this message translates to:
  /// **'0–30 days'**
  String get khataBucket0to30;

  /// No description provided for @khataBucket31to60.
  ///
  /// In en, this message translates to:
  /// **'31–60 days'**
  String get khataBucket31to60;

  /// No description provided for @khataBucket61to90.
  ///
  /// In en, this message translates to:
  /// **'61–90 days'**
  String get khataBucket61to90;

  /// No description provided for @khataBucket90plus.
  ///
  /// In en, this message translates to:
  /// **'90+ days'**
  String get khataBucket90plus;

  /// No description provided for @khataDueHarvest.
  ///
  /// In en, this message translates to:
  /// **'Due {date} · harvest {month}'**
  String khataDueHarvest(String date, String month);

  /// No description provided for @khataEntryOrder.
  ///
  /// In en, this message translates to:
  /// **'Sale on credit'**
  String get khataEntryOrder;

  /// No description provided for @khataEntryPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment received'**
  String get khataEntryPayment;

  /// No description provided for @khataEntryAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get khataEntryAdjustment;

  /// No description provided for @khataPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get khataPaymentHistory;

  /// No description provided for @khataNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payments yet'**
  String get khataNoPayments;

  /// No description provided for @khataPendingCollections.
  ///
  /// In en, this message translates to:
  /// **'Collected, not yet on the khata'**
  String get khataPendingCollections;

  /// No description provided for @collectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get collectionsTitle;

  /// No description provided for @collectionsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get collectionsToday;

  /// No description provided for @collectionsWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get collectionsWeek;

  /// No description provided for @collectionsTotal.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get collectionsTotal;

  /// No description provided for @collectionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No collections yet'**
  String get collectionsEmpty;

  /// No description provided for @collectionsEmptyHelp.
  ///
  /// In en, this message translates to:
  /// **'Payments you collect show here.'**
  String get collectionsEmptyHelp;

  /// No description provided for @collectionStateWaitingToSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get collectionStateWaitingToSync;

  /// No description provided for @collectionStatePendingReconciliation.
  ///
  /// In en, this message translates to:
  /// **'Pending reconciliation'**
  String get collectionStatePendingReconciliation;

  /// No description provided for @collectionStateWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment'**
  String get collectionStateWaiting;

  /// No description provided for @collectionStatePaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get collectionStatePaid;

  /// No description provided for @collectionStateOnKhata.
  ///
  /// In en, this message translates to:
  /// **'On khata'**
  String get collectionStateOnKhata;

  /// No description provided for @collectionStateApprovalNeeded.
  ///
  /// In en, this message translates to:
  /// **'Approval needed'**
  String get collectionStateApprovalNeeded;

  /// No description provided for @collectionStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get collectionStateFailed;

  /// No description provided for @syncEntityOrder.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get syncEntityOrder;

  /// No description provided for @syncEntityPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get syncEntityPayment;
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
