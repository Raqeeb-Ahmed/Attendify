import { useState, useEffect } from 'react';
import { db } from '../firebase/config';
import { collection, query, where, getDocs, orderBy } from 'firebase/firestore';
import { useAuth } from '../hooks/useAuth';
import { CURRENCY } from '../constants/hcm';
import { FaFileInvoiceDollar, FaDownload, FaEye } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';

export default function Payslips() {
  const { user } = useAuth();
  const [payslips, setPayslips] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedPayslip, setSelectedPayslip] = useState(null);

  useEffect(() => {
    if (user) fetchPayslips();
  }, [user]);

  const fetchPayslips = async () => {
    setLoading(true);
    try {
      const q = query(
        collection(db, 'payroll'),
        where('userId', '==', user.uid),
        orderBy('month', 'desc')
      );
      const querySnapshot = await getDocs(q);
      setPayslips(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching payslips:", error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">My Payslips</h1>
        <p className="text-gray-500 text-sm">View and download your monthly salary statements.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {loading ? (
          <div className="col-span-full text-center py-10 text-gray-500">Loading your payslips...</div>
        ) : payslips.length === 0 ? (
          <div className="col-span-full text-center py-10 text-gray-500">No payslips found yet.</div>
        ) : payslips.map((pay) => (
          <motion.div 
            key={pay.id}
            whileHover={{ y: -5 }}
            className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 space-y-4 hover:shadow-md transition-all"
          >
            <div className="flex justify-between items-start">
              <div className="p-3 bg-indigo-50 rounded-xl text-indigo-600">
                <FaFileInvoiceDollar className="text-2xl" />
              </div>
              <span className="px-3 py-1 bg-green-100 text-green-700 rounded-full text-xs font-bold uppercase tracking-wider">
                {pay.status}
              </span>
            </div>
            <div>
              <h3 className="text-lg font-bold text-gray-900">{new Date(pay.month + '-01').toLocaleDateString('default', { month: 'long', year: 'numeric' })}</h3>
              <p className="text-xs text-gray-400">Processed on {new Date(pay.processedAt).toLocaleDateString()}</p>
            </div>
            <div className="pt-4 border-t border-gray-50 flex justify-between items-end">
              <div>
                <p className="text-xs font-bold text-gray-400 uppercase">Net Salary</p>
                <p className="text-xl font-bold text-gray-900">{CURRENCY} {pay.netSalary.toLocaleString()}</p>
              </div>
              <button 
                onClick={() => setSelectedPayslip(pay)}
                className="p-2 text-indigo-600 hover:bg-indigo-50 rounded-lg transition-colors"
                title="View Details"
              >
                <FaEye className="text-xl" />
              </button>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Payslip Detail Modal */}
      <AnimatePresence>
        {selectedPayslip && (
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
                    <h2 className="text-2xl font-bold text-gray-900">Payslip Statement</h2>
                    <p className="text-gray-500 font-medium">{new Date(selectedPayslip.month + '-01').toLocaleDateString('default', { month: 'long', year: 'numeric' })}</p>
                  </div>
                  <div className="text-right text-sm text-gray-500">
                    <p className="font-bold text-gray-900">Core Flow HCM</p>
                    <p>Internal Revenue Service</p>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-8">
                  <div className="space-y-4">
                    <h3 className="text-xs font-bold text-gray-400 uppercase tracking-widest">Earnings</h3>
                    <div className="space-y-2">
                      <div className="flex justify-between text-sm">
                        <span className="text-gray-600">Base Salary</span>
                        <span className="font-semibold text-gray-900">{CURRENCY} {selectedPayslip.baseSalary.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between text-sm">
                        <span className="text-gray-600">Allowances</span>
                        <span className="font-semibold text-gray-900">{CURRENCY} {selectedPayslip.allowances.toLocaleString()}</span>
                      </div>
                    </div>
                  </div>
                  <div className="space-y-4">
                    <h3 className="text-xs font-bold text-gray-400 uppercase tracking-widest">Deductions</h3>
                    <div className="space-y-2">
                      {selectedPayslip.tax > 0 && (
                        <div className="flex justify-between text-sm">
                          <span className="text-gray-600">Income Tax</span>
                          <span className="font-semibold text-red-600">-{CURRENCY} {selectedPayslip.tax.toLocaleString()}</span>
                        </div>
                      )}
                      {selectedPayslip.deductions > 0 && (
                        <div className="flex justify-between text-sm">
                          <span className="text-gray-600">Other Deductions</span>
                          <span className="font-semibold text-red-600">-{CURRENCY} {selectedPayslip.deductions.toLocaleString()}</span>
                        </div>
                      )}
                      {selectedPayslip.advance > 0 && (
                        <div className="flex justify-between text-sm">
                          <span className="text-gray-600">Advance Salary</span>
                          <span className="font-semibold text-red-600">-{CURRENCY} {selectedPayslip.advance.toLocaleString()}</span>
                        </div>
                      )}
                      {!(selectedPayslip.tax > 0 || selectedPayslip.deductions > 0 || selectedPayslip.advance > 0) && (
                        <p className="text-xs text-gray-400 italic">No deductions this month.</p>
                      )}
                    </div>
                  </div>
                </div>

                <div className="bg-gray-50 p-6 rounded-2xl flex justify-between items-center border border-gray-100">
                  <div>
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-widest">Net Payable</p>
                    <p className="text-3xl font-bold text-indigo-600">{CURRENCY} {selectedPayslip.netSalary.toLocaleString()}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-xs font-medium text-gray-500 italic">Total salary credited to your account.</p>
                  </div>
                </div>

                <div className="flex justify-end gap-3 pt-4">
                  <button 
                    onClick={() => setSelectedPayslip(null)}
                    className="px-6 py-2 text-sm font-semibold text-gray-600 hover:text-gray-900"
                  >
                    Close
                  </button>
                  <button 
                    onClick={() => window.print()}
                    className="flex items-center gap-2 px-6 py-2 bg-indigo-600 text-white rounded-xl font-semibold text-sm shadow-md hover:bg-indigo-700 transition-all"
                  >
                    <FaDownload /> Download PDF
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
