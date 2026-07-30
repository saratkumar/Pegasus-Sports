function fmtDate(d) {
  const day = d.getDate().toString().padStart(2, "0");
  const month = (d.getMonth() + 1).toString().padStart(2, "0");
  return `${day}/${month}/${d.getFullYear()}`;
}

// Mirrors the visual language of lib/services/email_service.dart and
// invoice_service.dart (sans-serif, #0A0A0A body text, #FF7A00 accents) so
// it doesn't look like a different product. The CTA is a real <a href> —
// not JS — since email clients strip onclick handlers; pegasus://renew is
// the app's custom URL scheme (see deep_link_service.dart).
//
// Content is a scannable "plan summary" card (plan / expiry / credits left)
// rather than a prose paragraph, so the recipient doesn't have to read
// closely to know exactly what's expiring and when.
function buildRenewalReminderEmail({ to, name, planName, endDate, creditsRemaining, daysLeft }) {
  const dateStr = fmtDate(endDate);
  const dayLabel = daysLeft === 1 ? "1 day left" : `${daysLeft} days left`;
  const hasCredits = creditsRemaining > 0;

  const creditsRow = hasCredits
    ? `
        <tr>
          <td style="padding: 6px 14px 12px; color: #666666;">Credits remaining</td>
          <td style="padding: 6px 14px 12px; text-align: right; font-weight: bold;">${creditsRemaining}</td>
        </tr>`
    : "";

  const consequenceText = hasCredits
    ? `Once ${planName} ends, you won't be able to book new classes until you renew — and your remaining ${creditsRemaining} credit${
        creditsRemaining === 1 ? "" : "s"
      } won't carry over to a new plan.`
    : `Once ${planName} ends, you won't be able to book new classes until you renew.`;

  const html = `
    <div style="font-family: sans-serif; color: #0A0A0A; max-width: 480px; margin: 0 auto;">
      <h2 style="color: #FF7A00; margin: 0 0 16px;">Your membership is expiring soon</h2>
      <p style="margin: 0 0 16px;">Hi ${name}, here's a quick summary of your plan:</p>

      <table style="width: 100%; border-collapse: collapse; font-size: 14px;
                     border: 1px solid #eeeeee; border-radius: 8px; margin: 0 0 20px;">
        <tr>
          <td style="padding: 12px 14px 6px; color: #666666;">Plan</td>
          <td style="padding: 12px 14px 6px; text-align: right; font-weight: bold;">${planName}</td>
        </tr>
        <tr>
          <td style="padding: ${hasCredits ? "6px 14px" : "6px 14px 12px"}; color: #666666;">Expires on</td>
          <td style="padding: ${hasCredits ? "6px 14px" : "6px 14px 12px"}; text-align: right; font-weight: bold; color: #FF7A00;">
            ${dateStr} &middot; ${dayLabel}
          </td>
        </tr>${creditsRow}
      </table>

      <p style="margin: 0 0 24px;">${consequenceText}</p>

      <div style="text-align: center; margin: 0 0 20px;">
        <a href="pegasus://renew"
           style="display: inline-block; background-color: #FF7A00; color: #ffffff;
                  font-weight: bold; text-decoration: none; padding: 14px 28px;
                  border-radius: 8px; font-family: sans-serif; font-size: 15px;">
          Renew My Plan
        </a>
      </div>
      <p style="margin: 0 0 24px; color: #666666; font-size: 12px; text-align: center;">
        Or open the PSAS app and go to Membership to renew.
      </p>
      <p style="color: #666666; font-size: 12px;">
        Questions? <a href="mailto:admin.psas@gmail.com">admin.psas@gmail.com</a>
      </p>
    </div>
  `;

  return {
    to: [to],
    message: {
      subject: `Your ${planName} plan expires in ${daysLeft === 1 ? "1 day" : `${daysLeft} days`}`,
      html,
    },
  };
}

module.exports = { buildRenewalReminderEmail };
