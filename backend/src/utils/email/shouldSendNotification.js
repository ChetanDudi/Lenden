function shouldSendNotification(user) {
  if (!user.notificationSettings || !user.notificationSettings.quietHoursEnabled) {
    return true; // Send if quiet hours are not enabled
  }

  const { quietHoursStart, quietHoursEnd } = user.notificationSettings;

  // Basic validation
  if (!quietHoursStart || !quietHoursEnd) {
    return true;
  }

  try {
    const now = new Date();
    const currentTime = now.getHours() * 60 + now.getMinutes();

    const [startHour, startMinute] = quietHoursStart.split(':').map(Number);
    const startTime = startHour * 60 + startMinute;

    const [endHour, endMinute] = quietHoursEnd.split(':').map(Number);
    const endTime = endHour * 60 + endMinute;

    // Case 1: Quiet hours do not span across midnight (e.g., 08:00 to 22:00)
    if (startTime <= endTime) {
      if (currentTime >= startTime && currentTime < endTime) {
        return false; // It's quiet time
      }
    } 
    // Case 2: Quiet hours span across midnight (e.g., 22:00 to 08:00)
    else {
      if (currentTime >= startTime || currentTime < endTime) {
        return false; // It's quiet time
      }
    }

    return true; // It's not quiet time
  } catch (error) {
    console.error("Error processing quiet hours:", error);
    return true; // Fail open: send notification if there's an error
  }
}

module.exports = { shouldSendNotification };
