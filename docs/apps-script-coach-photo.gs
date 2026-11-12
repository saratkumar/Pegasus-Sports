// Add this to the Apps Script project behind APPS_SCRIPT_URL (the one that
// writes the ActivityLog / Transactions Sheet). Called only by the
// `uploadCoachPhoto` Cloud Function (functions/index.js), which has already
// checked the caller is an admin.
//
// If the script ALREADY has a doPost function, don't add a second one:
// copy the `if (body.action === 'upload_coach_photo')` branch into it.
//
// After pasting:
//   1. Select `authorizeDrive` in the toolbar and click Run once — approve
//      the new Google Drive permission.
//   2. Deploy → Manage deployments → pencil icon on the current deployment →
//      Version: "New version" → Deploy. (Editing the existing deployment
//      keeps the same URL, so nothing in Firebase needs changing.)

const COACH_PHOTO_FOLDER = 'Pegasus Coach Photos';

function doPost(e) {
  let body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return json_({ error: 'Invalid JSON' });
  }

  if (body.action === 'upload_coach_photo') {
    try {
      const bytes = Utilities.base64Decode(body.data);
      const blob = Utilities.newBlob(bytes, body.mimeType, body.fileName);
      const file = coachPhotoFolder_().createFile(blob);
      // Members' apps load the photo directly, so it must be viewable by
      // anyone with the link (not listed or searchable).
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      return json_({ fileId: file.getId() });
    } catch (err) {
      return json_({ error: String(err) });
    }
  }

  return json_({ error: 'Unsupported action: ' + body.action });
}

function coachPhotoFolder_() {
  const found = DriveApp.getFoldersByName(COACH_PHOTO_FOLDER);
  return found.hasNext() ? found.next() : DriveApp.createFolder(COACH_PHOTO_FOLDER);
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

// Run once from the editor to grant the Drive permission.
function authorizeDrive() {
  coachPhotoFolder_();
}
