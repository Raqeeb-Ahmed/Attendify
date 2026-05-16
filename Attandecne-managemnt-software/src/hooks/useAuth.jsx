import { useState, useEffect, createContext, useContext } from 'react';
import { auth, db, rtdb } from '../firebase/config';
import { onAuthStateChanged, signInWithPopup, signOut } from 'firebase/auth';
import { googleProvider } from '../firebase/config';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { ref, set } from 'firebase/database';
import { checkOut } from '../services/attendance';

const AuthContext = createContext();

const ALLOWED_DOMAIN = import.meta.env.VITE_ALLOWED_DOMAIN || "gmail.com";

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (firebaseUser) => {
      try {
        if (firebaseUser) {
          // Domain validation - allow for development
          if (!firebaseUser.email.endsWith(`@${ALLOWED_DOMAIN}`) && ALLOWED_DOMAIN !== 'yourcompany.com' && ALLOWED_DOMAIN !== 'gmail.com') {
            console.warn(`Email ${firebaseUser.email} does not match allowed domain ${ALLOWED_DOMAIN}`);
          }

          const userRef = doc(db, 'users', firebaseUser.uid);
          const userSnap = await getDoc(userRef);

          let userData = {
            uid: firebaseUser.uid,
            email: firebaseUser.email,
            name: firebaseUser.displayName,
            photoURL: firebaseUser.photoURL,
            role: 'employee', 
          };

          if (userSnap.exists()) {
            userData = { ...userData, ...userSnap.data() };
          } else {
            await setDoc(userRef, {
              email: firebaseUser.email,
              name: firebaseUser.displayName,
              role: 'employee',
              createdAt: new Date().toISOString()
            });
          }
          setUser(userData);
        } else {
          setUser(null);
        }
      } catch (error) {
        console.error("Auth state change error:", error);
        setUser(null);
      } finally {
        setLoading(false);
      }
    });

    return unsubscribe;
  }, []);

  const loginContext = async () => {
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (error) {
      console.error("Login failed:", error);
      throw error;
    }
  };

  const logoutContext = async () => {
    try {
      const currentUser = auth.currentUser;
      if (currentUser) {
        // 1. Auto check-out the session
        await checkOut(currentUser.uid);

        // 2. Mark heartbeat offline
        await setDoc(doc(db, 'heartbeats', currentUser.uid), {
          userId: currentUser.uid,
          lastSeen: new Date().toISOString(),
          online: false,
        });

        // 3. Mark RTDB presence offline
        try {
          const presenceRef = ref(rtdb, `presence/${currentUser.uid}`);
          await set(presenceRef, { online: false, lastSeen: new Date().toISOString() });
        } catch (e) {
          console.warn("RTDB offline mark failed", e);
        }
      }
    } catch (e) {
      console.warn("Logout cleanup failed", e);
    }
    await signOut(auth);
  };

  return (
    <AuthContext.Provider value={{ user, loading, loginContext, logoutContext }}>
      {!loading && children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
