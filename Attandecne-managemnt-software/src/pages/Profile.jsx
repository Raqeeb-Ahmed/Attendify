import { useState } from 'react';
import { useAuth } from '../hooks/useAuth';
import { db } from '../firebase/config';
import { doc, updateDoc } from 'firebase/firestore';
import { FaUser, FaEnvelope, FaBuilding, FaPhone, FaCalendarAlt, FaIdBadge, FaEdit, FaSave, FaTimes } from 'react-icons/fa';
import { motion } from 'framer-motion';

export default function Profile() {
  const { user } = useAuth();
  const [isEditing, setIsEditing] = useState(false);
  const [phone, setPhone] = useState(user?.phone || '');
  const [loading, setLoading] = useState(false);

  const handleUpdate = async () => {
    setLoading(true);
    try {
      await updateDoc(doc(db, 'users', user.uid), {
        phone: phone
      });
      setIsEditing(false);
      // Note: The user object in useAuth might need a refresh or the user can just reload.
      // In a real app, I'd update the context state too.
      window.location.reload();
    } catch (error) {
      console.error("Error updating profile:", error);
    } finally {
      setLoading(false);
    }
  };

  const profileFields = [
    { label: 'Full Name', value: user?.name, icon: <FaUser className="text-blue-500" />, editable: false },
    { label: 'Email Address', value: user?.email, icon: <FaEnvelope className="text-red-500" />, editable: false },
    { label: 'Department', value: user?.department || 'Not Assigned', icon: <FaBuilding className="text-indigo-500" />, editable: false },
    { label: 'Designation', value: user?.designation || 'Not Assigned', icon: <FaIdBadge className="text-purple-500" />, editable: false },
    { label: 'Phone', value: user?.phone || 'Not Provided', icon: <FaPhone className="text-green-500" />, editable: true },
    { label: 'Joining Date', value: user?.joiningDate || 'N/A', icon: <FaCalendarAlt className="text-orange-500" />, editable: false },
  ];

  return (
    <div className="max-w-4xl mx-auto space-y-8">
      <div className="bg-white rounded-3xl shadow-xl overflow-hidden border border-gray-100">
        <div className="h-48 bg-gradient-to-r from-indigo-600 to-purple-600 relative">
          <div className="absolute -bottom-16 left-8">
            <img
              src={user?.photoURL || 'https://via.placeholder.com/150'}
              alt="Profile"
              className="h-32 w-32 rounded-3xl border-4 border-white shadow-2xl object-cover bg-white"
            />
          </div>
          <div className="absolute bottom-4 right-8">
            {!isEditing ? (
              <button
                onClick={() => setIsEditing(true)}
                className="flex items-center gap-2 px-6 py-2 bg-white/20 backdrop-blur-md text-white rounded-xl font-bold border border-white/30 hover:bg-white/30 transition-all"
              >
                <FaEdit /> Edit Profile
              </button>
            ) : (
              <div className="flex gap-2">
                <button
                  onClick={handleUpdate}
                  disabled={loading}
                  className="flex items-center gap-2 px-6 py-2 bg-green-500 text-white rounded-xl font-bold shadow-lg hover:bg-green-600 transition-all"
                >
                  <FaSave /> {loading ? 'Saving...' : 'Save Changes'}
                </button>
                <button
                  onClick={() => setIsEditing(false)}
                  className="flex items-center gap-2 px-6 py-2 bg-white/20 backdrop-blur-md text-white rounded-xl font-bold border border-white/30"
                >
                  <FaTimes /> Cancel
                </button>
              </div>
            )}
          </div>
        </div>

        <div className="pt-20 pb-10 px-8">
          <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">{user?.name}</h1>
              <p className="text-gray-500 font-medium">{user?.designation || 'New Employee'} • {user?.department || 'General'}</p>
            </div>
            <div className="flex gap-2">
              <span className="px-4 py-1.5 bg-green-100 text-green-700 rounded-full text-sm font-bold border border-green-200 uppercase tracking-wider">
                {user?.status || 'Active'}
              </span>
              <span className="px-4 py-1.5 bg-indigo-100 text-indigo-700 rounded-full text-sm font-bold border border-indigo-200 uppercase tracking-wider">
                {user?.role}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {profileFields.map((field, idx) => (
          <motion.div
            key={idx}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: idx * 0.1 }}
            className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 flex items-center space-x-4 hover:shadow-md transition-shadow"
          >
            <div className="p-3 bg-gray-50 rounded-xl">
              {field.icon}
            </div>
            <div className="flex-1">
              <p className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-1">{field.label}</p>
              {isEditing && field.editable ? (
                <input
                  type="text"
                  className="w-full bg-indigo-50 border-b-2 border-indigo-500 py-1 outline-none text-lg font-semibold text-indigo-900"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  autoFocus
                />
              ) : (
                <p className="text-lg font-semibold text-gray-800">{field.value}</p>
              )}
            </div>
          </motion.div>
        ))}
      </div>
    </div>
  );
}
