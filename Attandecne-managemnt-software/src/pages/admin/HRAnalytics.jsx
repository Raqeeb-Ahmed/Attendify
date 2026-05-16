import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, query, orderBy } from 'firebase/firestore';
import { FaUsers, FaCalendarAlt, FaMoneyBillWave, FaStar, FaChartPie, FaArrowUp, FaArrowDown, FaWallet, FaChartBar } from 'react-icons/fa';
import { motion } from 'framer-motion';
import { DEPARTMENTS } from '../../constants/hcm';

export default function HRAnalytics() {
  const [stats, setStats] = useState({
    totalEmployees: 0,
    activeLeaves: 0,
    monthlyPayroll: 0,
    totalExpenses: 0,
    avgPerformance: 0,
    deptDistribution: {},
    expenseCategories: {},
    attendanceRate: 94
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchAnalytics();
  }, []);

  const fetchAnalytics = async () => {
    setLoading(true);
    try {
      const empSnap = await getDocs(collection(db, 'users'));
      const employees = empSnap.docs.map(doc => doc.data()).filter(e => e.role !== 'admin');
      
      const appSnap = await getDocs(collection(db, 'appraisals'));
      const appraisals = appSnap.docs.map(doc => doc.data());

      const leaveSnap = await getDocs(collection(db, 'leaves'));
      const leaves = leaveSnap.docs.map(doc => doc.data()).filter(l => l.status === 'approved');

      const expSnap = await getDocs(collection(db, 'expenses'));
      const expenses = expSnap.docs.map(doc => doc.data()).filter(e => e.status === 'approved');

      // Calculations
      const deptDist = {};
      employees.forEach(e => {
        deptDist[e.department] = (deptDist[e.department] || 0) + 1;
      });

      const expDist = {};
      let totalExp = 0;
      expenses.forEach(e => {
        const amt = Number(e.amount) || 0;
        expDist[e.category || 'Other'] = (expDist[e.category || 'Other'] || 0) + amt;
        totalExp += amt;
      });

      const totalPayroll = employees.reduce((acc, e) => acc + (Number(e.salary) || 0) + (Number(e.allowances) || 0), 0);
      const avgPerf = appraisals.length > 0 ? appraisals.reduce((acc, a) => acc + a.rating, 0) / appraisals.length : 0;

      setStats({
        totalEmployees: employees.length,
        activeLeaves: leaves.length,
        monthlyPayroll: totalPayroll,
        totalExpenses: totalExp,
        avgPerformance: avgPerf.toFixed(1),
        deptDistribution: deptDist,
        expenseCategories: expDist,
        attendanceRate: 92 + Math.random() * 5 // Simulated for demo
      });
    } catch (error) {
      console.error("Error fetching analytics:", error);
    } finally {
      setLoading(false);
    }
  };

  const statCards = [
    { label: 'Total Employees', value: stats.totalEmployees, icon: <FaUsers />, color: 'bg-indigo-500', trend: '+2%', positive: true },
    { label: 'Monthly Salary Base', value: `PKR ${stats.monthlyPayroll.toLocaleString()}`, icon: <FaMoneyBillWave />, color: 'bg-emerald-500', trend: '+1.2%', positive: false },
    { label: 'Approved Expenses', value: `PKR ${stats.totalExpenses.toLocaleString()}`, icon: <FaWallet />, color: 'bg-rose-500', trend: '-5%', positive: true },
    { label: 'Avg. Performance', value: `${stats.avgPerformance}/5`, icon: <FaStar />, color: 'bg-amber-500', trend: '+5%', positive: true },
  ];

  // For Financial Bar Chart
  const maxFinancialValue = Math.max(stats.monthlyPayroll, stats.totalExpenses, 1);
  const payrollHeight = (stats.monthlyPayroll / maxFinancialValue) * 100;
  const expensesHeight = (stats.totalExpenses / maxFinancialValue) * 100;

  return (
    <div className="space-y-8 pb-12">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Reports & Analytics</h1>
        <p className="text-gray-500 text-sm mt-1">Comprehensive overview of workforce metrics, salaries, and company expenses.</p>
      </div>

      {/* Top Stat Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {statCards.map((card, i) => (
          <motion.div 
            key={i}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.1 }}
            className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 flex flex-col justify-between"
          >
            <div className="flex justify-between items-start mb-4">
              <div className={`p-3 rounded-xl text-white ${card.color} shadow-sm`}>
                {card.icon}
              </div>
              <div className={`flex items-center text-[10px] font-bold px-2 py-1 rounded-lg ${card.positive ? 'bg-green-50 text-green-600' : 'bg-red-50 text-red-600'}`}>
                {card.positive ? <FaArrowUp className="mr-1" /> : <FaArrowDown className="mr-1" />} {card.trend}
              </div>
            </div>
            <div>
              <p className="text-xs font-bold text-gray-400 uppercase tracking-wide">{card.label}</p>
              <h3 className="text-2xl font-black text-gray-900 mt-1">{loading ? '...' : card.value}</h3>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        
        {/* Financial Overview (Bar Chart) */}
        <div className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 flex flex-col">
          <div className="flex items-center gap-3 mb-8">
            <div className="p-2 bg-indigo-50 text-indigo-600 rounded-lg"><FaChartBar /></div>
            <div>
              <h3 className="font-bold text-gray-900 text-lg">Financial Overview</h3>
              <p className="text-xs text-gray-500">Salaries vs Approved Expenses</p>
            </div>
          </div>
          
          <div className="flex-1 flex items-end justify-center gap-12 sm:gap-24 h-64 pt-10 pb-4 border-b border-gray-100 relative">
            {/* Background Grid Lines */}
            <div className="absolute inset-0 flex flex-col justify-between pointer-events-none pb-4 opacity-30">
              <div className="border-t border-gray-200 w-full"></div>
              <div className="border-t border-gray-200 w-full"></div>
              <div className="border-t border-gray-200 w-full"></div>
              <div className="border-t border-gray-200 w-full"></div>
            </div>

            {/* Payroll Bar */}
            <div className="flex flex-col items-center gap-3 z-10 w-20">
              <span className="text-sm font-bold text-gray-700">PKR {stats.monthlyPayroll.toLocaleString()}</span>
              <motion.div 
                initial={{ height: 0 }}
                animate={{ height: `${payrollHeight}%` }}
                transition={{ duration: 1, ease: "easeOut" }}
                className="w-full bg-gradient-to-t from-emerald-600 to-emerald-400 rounded-t-xl shadow-lg"
              ></motion.div>
              <span className="text-xs font-bold text-gray-500 uppercase">Payroll</span>
            </div>

            {/* Expenses Bar */}
            <div className="flex flex-col items-center gap-3 z-10 w-20">
              <span className="text-sm font-bold text-gray-700">PKR {stats.totalExpenses.toLocaleString()}</span>
              <motion.div 
                initial={{ height: 0 }}
                animate={{ height: `${expensesHeight}%` }}
                transition={{ duration: 1, ease: "easeOut", delay: 0.2 }}
                className="w-full bg-gradient-to-t from-rose-600 to-rose-400 rounded-t-xl shadow-lg"
              ></motion.div>
              <span className="text-xs font-bold text-gray-500 uppercase">Expenses</span>
            </div>
          </div>
          <div className="mt-6 flex justify-center gap-6 text-xs font-bold text-gray-500">
             <div className="flex items-center gap-2"><div className="w-3 h-3 rounded-full bg-emerald-500"></div> Total Salaries</div>
             <div className="flex items-center gap-2"><div className="w-3 h-3 rounded-full bg-rose-500"></div> Reimbursed Expenses</div>
          </div>
        </div>

        {/* Department Distribution (Progress Bars) */}
        <div className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100">
          <div className="flex items-center gap-3 mb-8">
            <div className="p-2 bg-blue-50 text-blue-600 rounded-lg"><FaChartPie /></div>
            <div>
              <h3 className="font-bold text-gray-900 text-lg">Department Distribution</h3>
              <p className="text-xs text-gray-500">Workforce allocation across teams</p>
            </div>
          </div>
          <div className="space-y-6">
            {DEPARTMENTS.map((dept, i) => {
              const count = stats.deptDistribution[dept] || 0;
              const percent = stats.totalEmployees > 0 ? (count / stats.totalEmployees) * 100 : 0;
              return (
                <div key={dept} className="space-y-2">
                  <div className="flex justify-between text-sm font-bold">
                    <span className="text-gray-700">{dept}</span>
                    <span className="text-gray-500">{count} Staff <span className="text-gray-300 mx-1">|</span> {percent.toFixed(0)}%</span>
                  </div>
                  <div className="w-full bg-gray-100 rounded-full h-3 overflow-hidden">
                    <motion.div 
                      initial={{ width: 0 }}
                      animate={{ width: `${percent}%` }}
                      transition={{ duration: 1, delay: i * 0.1 }}
                      className={`h-full rounded-full ${['bg-indigo-500', 'bg-blue-500', 'bg-cyan-500', 'bg-teal-500', 'bg-emerald-500'][i % 5]}`}
                    ></motion.div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Expense Category Breakdown */}
        <div className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 lg:col-span-2">
          <div className="flex items-center gap-3 mb-6">
            <div className="p-2 bg-orange-50 text-orange-600 rounded-lg"><FaWallet /></div>
            <div>
              <h3 className="font-bold text-gray-900 text-lg">Expense Breakdown</h3>
              <p className="text-xs text-gray-500">Approved claims by category</p>
            </div>
          </div>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4">
            {Object.keys(stats.expenseCategories).length === 0 ? (
               <div className="col-span-full py-8 text-center text-gray-400 font-medium text-sm">No expenses recorded yet.</div>
            ) : (
              Object.entries(stats.expenseCategories).map(([category, amount], i) => {
                const percent = stats.totalExpenses > 0 ? (amount / stats.totalExpenses) * 100 : 0;
                return (
                  <motion.div 
                    key={category}
                    initial={{ opacity: 0, scale: 0.9 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ delay: i * 0.1 }}
                    className="p-4 border border-gray-100 rounded-xl bg-gray-50"
                  >
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-1">{category}</p>
                    <h4 className="text-xl font-black text-gray-800">PKR {amount.toLocaleString()}</h4>
                    <div className="mt-3 w-full bg-gray-200 rounded-full h-1.5 overflow-hidden">
                      <motion.div 
                        initial={{ width: 0 }}
                        animate={{ width: `${percent}%` }}
                        transition={{ duration: 1, delay: i * 0.1 + 0.5 }}
                        className="h-full bg-rose-500 rounded-full"
                      ></motion.div>
                    </div>
                    <p className="text-[10px] text-gray-500 mt-2 font-bold text-right">{percent.toFixed(1)}% of total</p>
                  </motion.div>
                )
              })
            )}
          </div>
        </div>
        
      </div>
    </div>
  );
}
