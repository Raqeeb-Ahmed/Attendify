import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, doc, setDoc } from 'firebase/firestore';
import { CURRENCY, DEFAULT_TAX_RATE } from '../../constants/hcm';
import { FaMoneyCheckAlt, FaCheckCircle, FaExclamationTriangle, FaSearch, FaCalendarAlt } from 'react-icons/fa';
import { format } from 'date-fns';
import { motion, AnimatePresence } from 'framer-motion';

export default function PayrollManagement() {
  const [employees, setEmployees] = useState([]);
  const [allPayroll, setAllPayroll] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selectedEmployee, setSelectedEmployee] = useState(null);
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear());
  const [processing, setProcessing] = useState(false);
  const [activePaymentMonth, setActivePaymentMonth] = useState(null);
  const [paymentDetails, setPaymentDetails] = useState({ deductions: 0, advance: 0 });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      // Fetch all employees
      const empSnapshot = await getDocs(collection(db, 'users'));
      const empList = empSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      setEmployees(empList.filter(e => e.role !== 'admin' || e.baseSalary > 0));

      // Fetch all payroll records
      const paySnapshot = await getDocs(collection(db, 'payroll'));
      setAllPayroll(paySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching payroll data:", error);
    } finally {
      setLoading(false);
    }
  };

  const markAsPaid = async (emp, monthStr, details = { deductions: 0, advance: 0 }) => {
    setProcessing(true);
    try {
      const base = emp.baseSalary || 0;
      const allowances = emp.allowances || 0;
      const tax = (base + allowances) * (DEFAULT_TAX_RATE / 100);
      const deductions = details.deductions || 0;
      const advance = details.advance || 0;
      const net = base + allowances - tax - deductions - advance;

      const payrollId = `${emp.id}_${monthStr}`;
      const newRecord = {
        userId: emp.id,
        userName: emp.name,
        month: monthStr,
        baseSalary: base,
        allowances,
        tax,
        deductions,
        advance,
        netSalary: net,
        status: 'paid',
        processedAt: new Date().toISOString()
      };
      
      await setDoc(doc(db, 'payroll', payrollId), newRecord);
      
      setAllPayroll(prev => {
        const filtered = prev.filter(p => p.id !== payrollId);
        return [...filtered, { id: payrollId, ...newRecord }];
      });
      setActivePaymentMonth(null);
    } catch (error) {
      console.error("Failed to mark as paid:", error);
    } finally {
      setProcessing(false);
    }
  };

  const filteredEmployees = employees.filter(emp => 
    emp.name?.toLowerCase().includes(search.toLowerCase()) ||
    emp.email?.toLowerCase().includes(search.toLowerCase())
  );

  const months = Array.from({ length: 12 }, (_, i) => {
    const monthStr = `${selectedYear}-${String(i + 1).padStart(2, '0')}`;
    const d = new Date(selectedYear, i, 1);
    const monthName = d.toLocaleString('default', { month: 'long' });
    return { monthStr, monthName };
  });

  return (
    <div className="space-y-6 pb-10">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Payroll Management</h1>
          <p className="text-gray-500 text-sm mt-1">Manage employee salaries and track monthly payments.</p>
        </div>
        <div className="flex flex-col sm:flex-row items-center gap-3 w-full md:w-auto">
          <div className="relative w-full sm:w-64">
            <FaSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input 
              type="text" 
              placeholder="Search employee..."
              className="w-full pl-10 pr-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500 text-sm shadow-sm"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <select
            value={selectedYear}
            onChange={(e) => setSelectedYear(Number(e.target.value))}
            className="w-full sm:w-auto px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500 font-medium text-gray-700 bg-white shadow-sm"
          >
            {[...Array(5)].map((_, i) => {
              const y = new Date().getFullYear() - i;
              return <option key={y} value={y}>{y}</option>;
            })}
          </select>
        </div>
      </div>

      {loading ? (
        <div className="text-center py-16 text-gray-500">
          <div className="w-8 h-8 border-4 border-indigo-200 border-t-indigo-600 rounded-full animate-spin mx-auto mb-3"></div>
          Loading payroll data...
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {filteredEmployees.map(emp => {
            const empPayrollThisYear = allPayroll.filter(p => p.userId === emp.id && p.month.startsWith(String(selectedYear)));
            const totalPaid = empPayrollThisYear.reduce((sum, p) => sum + (p.netSalary || 0), 0);
            const monthsPaid = empPayrollThisYear.length;

            return (
              <div 
                key={emp.id}
                onClick={() => setSelectedEmployee(emp)}
                className="bg-white border border-gray-200 rounded-xl p-5 cursor-pointer hover:shadow-lg hover:border-indigo-400 transition-all flex flex-col group"
              >
                <div className="flex items-center gap-4 mb-5">
                  <img src={emp.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(emp.name || 'U')}&background=e0e7ff&color=4f46e5`} className="w-14 h-14 rounded-full object-cover border-2 border-white shadow-sm" alt="" />
                  <div className="flex-1 min-w-0">
                    <h3 className="font-bold text-gray-900 truncate group-hover:text-indigo-600 transition-colors">{emp.name}</h3>
                    <p className="text-xs text-gray-500 truncate">{emp.designation || 'Staff'}</p>
                  </div>
                </div>
                
                <div className="bg-gray-50 rounded-lg p-3 mb-4 border border-gray-100 flex items-center justify-between">
                  <div>
                    <p className="text-[10px] uppercase font-bold text-gray-400 tracking-wider">Net Salary / mo</p>
                    <p className="text-sm font-bold text-gray-800">
                      {CURRENCY} {((emp.baseSalary || 0) + (emp.allowances || 0) - ((emp.baseSalary || 0) + (emp.allowances || 0)) * (DEFAULT_TAX_RATE/100)).toLocaleString()}
                    </p>
                  </div>
                  <FaMoneyCheckAlt className="text-indigo-200 text-2xl" />
                </div>

                <div className="flex justify-between items-end border-t border-gray-100 pt-4 mt-auto">
                  <div>
                    <p className="text-[10px] uppercase font-bold text-gray-400 tracking-wider mb-1">Total Paid ({selectedYear})</p>
                    <p className="text-lg font-bold text-emerald-600">{CURRENCY} {totalPaid.toLocaleString()}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-[10px] uppercase font-bold text-gray-400 tracking-wider mb-1">Months Paid</p>
                    <p className="text-sm font-bold text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded-full inline-block">{monthsPaid} / 12</p>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Employee Calendar Modal */}
      <AnimatePresence>
        {selectedEmployee && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 bg-gray-900/60 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              className="bg-gray-50 rounded-2xl shadow-2xl w-full max-w-5xl overflow-hidden max-h-[90vh] flex flex-col"
            >
              {/* Modal Header */}
              <div className="px-6 py-5 border-b border-gray-200 bg-white flex flex-col md:flex-row md:items-center justify-between gap-4 sticky top-0 z-10">
                <div className="flex items-center gap-4">
                  <img src={selectedEmployee.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(selectedEmployee.name || 'U')}&background=e0e7ff&color=4f46e5`} className="w-16 h-16 rounded-full border-4 border-white shadow-sm" alt="" />
                  <div>
                    <h2 className="text-xl font-bold text-gray-900">{selectedEmployee.name}</h2>
                    <p className="text-sm text-gray-500">{selectedEmployee.designation || 'Staff'} • {selectedEmployee.email}</p>
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <div className="hidden sm:block text-right mr-4 pr-4 border-r border-gray-200">
                    <p className="text-[10px] uppercase font-bold text-gray-400 tracking-wider">Salary Breakdown</p>
                    <div className="flex gap-3 mt-1">
                      <span className="text-xs text-gray-600">Base: <strong className="text-gray-900">{selectedEmployee.baseSalary || 0}</strong></span>
                      <span className="text-xs text-gray-600">Alw: <strong className="text-gray-900">{selectedEmployee.allowances || 0}</strong></span>
                      <span className="text-xs text-red-500">Tax: <strong>{DEFAULT_TAX_RATE}%</strong></span>
                    </div>
                  </div>
                  <button onClick={() => setSelectedEmployee(null)} className="text-gray-400 hover:text-gray-700 bg-gray-100 hover:bg-gray-200 p-2 rounded-full transition-colors">✕</button>
                </div>
              </div>
              
              {/* Calendar Grid */}
              <div className="flex-1 overflow-y-auto p-6">
                <div className="flex items-center justify-between mb-6">
                  <h3 className="text-lg font-bold text-gray-800 flex items-center gap-2">
                    <FaCalendarAlt className="text-indigo-600" /> Payroll Calendar {selectedYear}
                  </h3>
                </div>

                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                  {months.map(({ monthStr, monthName }) => {
                    const record = allPayroll.find(p => p.userId === selectedEmployee.id && p.month === monthStr);
                    const isPaid = !!record;
                    const isCurrentMonth = monthStr === format(new Date(), 'yyyy-MM');
                    const isFutureMonth = new Date(monthStr + '-01') > new Date();

                    return (
                      <div 
                        key={monthStr} 
                        className={`border rounded-xl p-5 flex flex-col items-center text-center relative overflow-hidden transition-all ${
                          isPaid ? 'border-green-200 bg-green-50/50 hover:bg-green-50' : 
                          isCurrentMonth ? 'border-indigo-300 bg-indigo-50 shadow-sm' : 
                          'border-gray-200 bg-white hover:border-indigo-200 hover:shadow-md'
                        }`}
                      >
                        {isCurrentMonth && !isPaid && (
                          <div className="absolute top-0 w-full h-1 bg-indigo-500 left-0"></div>
                        )}
                        <h4 className="font-bold text-gray-900 text-lg">{monthName}</h4>
                        <p className="text-xs text-gray-400 mb-4 font-medium tracking-widest">{selectedYear}</p>
                        
                        {isPaid ? (
                          <>
                            <div className="w-10 h-10 rounded-full bg-green-100 flex items-center justify-center mb-3 text-green-600 mt-2">
                              <FaCheckCircle className="text-xl" />
                            </div>
                            <p className="text-sm font-bold text-green-700 mb-1">{CURRENCY} {record.netSalary?.toLocaleString()}</p>
                            {(record.deductions > 0 || record.advance > 0) && (
                              <div className="text-[9px] text-gray-500 mb-1 flex gap-1 justify-center">
                                {record.deductions > 0 && <span className="bg-gray-100 px-1.5 py-0.5 rounded">Ded: -{record.deductions}</span>}
                                {record.advance > 0 && <span className="bg-gray-100 px-1.5 py-0.5 rounded">Adv: -{record.advance}</span>}
                              </div>
                            )}
                            <p className="text-[10px] text-green-600 font-medium">Paid on {format(new Date(record.processedAt), 'dd MMM yyyy')}</p>
                          </>
                        ) : activePaymentMonth === monthStr ? (
                          <div className="w-full text-left space-y-3 mt-4 animate-fadeIn">
                            <div>
                              <label className="text-[10px] font-bold text-gray-500 uppercase tracking-wide">Deductions</label>
                              <div className="relative mt-1">
                                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-[10px] font-bold">PKR</span>
                                <input type="number" className="w-full border border-gray-200 rounded-lg pl-7 pr-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 transition-all font-semibold text-gray-700" 
                                  placeholder="0"
                                  value={paymentDetails.deductions} onChange={e => setPaymentDetails(p => ({...p, deductions: e.target.value}))} />
                              </div>
                            </div>
                            <div>
                              <label className="text-[10px] font-bold text-gray-500 uppercase tracking-wide">Advance Sal.</label>
                              <div className="relative mt-1">
                                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-[10px] font-bold">PKR</span>
                                <input type="number" className="w-full border border-gray-200 rounded-lg pl-7 pr-3 py-2 text-sm outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 transition-all font-semibold text-gray-700" 
                                  placeholder="0"
                                  value={paymentDetails.advance} onChange={e => setPaymentDetails(p => ({...p, advance: e.target.value}))} />
                              </div>
                            </div>
                            <div className="flex justify-between items-center pt-3 border-t border-gray-100 mt-2">
                              <span className="text-[10px] text-gray-400 font-bold uppercase tracking-wider">Net Payout:</span>
                              <span className="text-lg font-black text-indigo-600">
                                {CURRENCY} {((selectedEmployee.baseSalary || 0) + (selectedEmployee.allowances || 0) - ((selectedEmployee.baseSalary || 0) + (selectedEmployee.allowances || 0))*(DEFAULT_TAX_RATE/100) - (Number(paymentDetails.deductions) || 0) - (Number(paymentDetails.advance) || 0)).toLocaleString()}
                              </span>
                            </div>
                            <div className="flex gap-2 pt-2">
                              <button onClick={() => setActivePaymentMonth(null)} className="flex-1 px-3 py-2.5 bg-gray-100 rounded-lg text-xs font-bold text-gray-600 hover:bg-gray-200 hover:text-gray-800 transition-all">Cancel</button>
                              <button onClick={() => markAsPaid(selectedEmployee, monthStr, { deductions: Number(paymentDetails.deductions) || 0, advance: Number(paymentDetails.advance) || 0 })} disabled={processing} className="flex-1 px-3 py-2.5 bg-indigo-600 rounded-lg text-xs font-bold text-white hover:bg-indigo-700 hover:shadow-md transition-all active:scale-95">{processing ? 'Saving...' : 'Confirm'}</button>
                            </div>
                          </div>
                        ) : (
                          <>
                            <div className={`w-10 h-10 rounded-full flex items-center justify-center mb-3 mt-2 ${isFutureMonth ? 'bg-gray-100 text-gray-300' : 'bg-amber-100 text-amber-500'}`}>
                              <FaExclamationTriangle className="text-xl" />
                            </div>
                            <p className="text-sm font-bold text-gray-400 mb-3">{isFutureMonth ? 'Upcoming' : 'Unpaid'}</p>
                            <button 
                              onClick={() => { setActivePaymentMonth(monthStr); setPaymentDetails({ deductions: '', advance: '' }); }}
                              disabled={processing || isFutureMonth}
                              className={`mt-auto px-4 py-2 rounded-lg text-xs font-bold transition-all w-full ${
                                isFutureMonth 
                                ? 'bg-gray-100 text-gray-400 cursor-not-allowed' 
                                : 'bg-indigo-600 text-white hover:bg-indigo-700 shadow-sm hover:shadow active:scale-95'
                              }`}
                            >
                              Mark as Paid
                            </button>
                          </>
                        )}
                      </div>
                    )
                  })}
                </div>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
