import { db } from '../firebase/config';
import { collection, addDoc } from 'firebase/firestore';

export const createNotification = async ({ userId, targetRole, title, message, type = 'info' }) => {
  try {
    await addDoc(collection(db, 'notifications'), {
      userId: userId || null, // Specific user to notify
      targetRole: targetRole || null, // Or notify all of a specific role (e.g. 'admin')
      title,
      message,
      type, // 'info', 'success', 'warning'
      readBy: [],
      createdAt: new Date().toISOString()
    });
  } catch (error) {
    console.error("Error creating notification", error);
  }
};
