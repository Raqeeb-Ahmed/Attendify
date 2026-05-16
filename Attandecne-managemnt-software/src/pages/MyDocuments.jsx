import { useState, useEffect } from 'react';
import { db } from '../firebase/config';
import { collection, query, where, getDocs, orderBy } from 'firebase/firestore';
import { useAuth } from '../hooks/useAuth';
import { DOCUMENT_TYPES } from '../constants/hcm';
import { FaFilePdf, FaDownload, FaEye, FaLock } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';

export default function MyDocuments() {
  const { user } = useAuth();
  const [documents, setDocuments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedDoc, setSelectedDoc] = useState(null);

  useEffect(() => {
    if (user) fetchMyDocs();
  }, [user]);

  const fetchMyDocs = async () => {
    setLoading(true);
    try {
      const q = query(
        collection(db, 'documents'),
        where('userId', '==', user.uid),
        orderBy('createdAt', 'desc')
      );
      const querySnapshot = await getDocs(q);
      setDocuments(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching documents:", error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">My Document Vault</h1>
        <p className="text-gray-500 text-sm">Access your official contracts, letters, and certificates.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {loading ? (
          <div className="col-span-full text-center py-10 text-gray-500">Loading your document vault...</div>
        ) : documents.length === 0 ? (
          <div className="col-span-full flex flex-col items-center justify-center py-20 bg-white rounded-3xl border border-dashed border-gray-200">
            <FaLock className="text-4xl text-gray-200 mb-4" />
            <p className="text-gray-400">No official documents issued yet.</p>
          </div>
        ) : documents.map((doc) => (
          <motion.div 
            key={doc.id}
            whileHover={{ y: -5 }}
            className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 flex flex-col justify-between hover:shadow-md transition-all"
          >
            <div className="space-y-4">
              <div className="flex justify-between items-start">
                <div className="p-3 bg-red-50 rounded-xl text-red-600">
                  <FaFilePdf className="text-2xl" />
                </div>
                <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest bg-gray-50 px-2 py-1 rounded">
                  {new Date(doc.createdAt).toLocaleDateString()}
                </span>
              </div>
              <div>
                <h3 className="text-lg font-bold text-gray-900 leading-tight mb-1">{DOCUMENT_TYPES.find(t => t.id === doc.type)?.label}</h3>
                {doc.subject && <p className="text-sm font-bold text-gray-600 line-clamp-1 italic">Sub: {doc.subject}</p>}
                <p className="text-[10px] text-indigo-600 font-bold uppercase mt-2">Core Flow HCM • Official Document</p>
              </div>
            </div>
            <div className="pt-6 mt-6 border-t border-gray-50 flex gap-2">
              <button 
                onClick={() => setSelectedDoc(doc)}
                className="flex-1 flex items-center justify-center gap-2 py-2 bg-gray-50 text-gray-600 rounded-lg text-xs font-bold hover:bg-gray-100 transition-colors"
              >
                <FaEye /> View
              </button>
              <button 
                className="flex-1 flex items-center justify-center gap-2 py-2 bg-indigo-50 text-indigo-600 rounded-lg text-xs font-bold hover:bg-indigo-100 transition-colors"
              >
                <FaDownload /> Download
              </button>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Document Viewer Modal */}
      <AnimatePresence>
        {selectedDoc && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="bg-white rounded-3xl shadow-2xl w-full max-w-2xl overflow-hidden"
            >
              <div className="p-8 space-y-8">
                <div className="flex justify-between items-start border-b border-gray-100 pb-6">
                  <div>
                    <h2 className="text-2xl font-bold text-gray-900 leading-tight">{DOCUMENT_TYPES.find(t => t.id === selectedDoc.type)?.label}</h2>
                    {selectedDoc.subject && <p className="text-lg font-bold text-indigo-600 mt-1 italic">Subject: {selectedDoc.subject}</p>}
                    <p className="text-gray-500 font-medium mt-2">Issued on {new Date(selectedDoc.createdAt).toLocaleDateString()}</p>
                  </div>
                  <button onClick={() => setSelectedDoc(null)} className="text-gray-400">✕</button>
                </div>

                <div className="bg-gray-50 p-8 rounded-2xl min-h-[300px] whitespace-pre-wrap font-serif text-gray-800 leading-relaxed">
                  {selectedDoc.content}
                </div>

                <div className="flex justify-end gap-3 pt-4 border-t border-gray-100">
                  <button 
                    onClick={() => setSelectedDoc(null)}
                    className="px-6 py-2 text-sm font-semibold text-gray-600 hover:text-gray-900"
                  >
                    Close
                  </button>
                  <button 
                    onClick={() => window.print()}
                    className="flex items-center gap-2 px-6 py-2 bg-indigo-600 text-white rounded-xl font-semibold text-sm shadow-md hover:bg-indigo-700 transition-all"
                  >
                    <FaDownload /> Print / Save
                  </button>
                </div>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
