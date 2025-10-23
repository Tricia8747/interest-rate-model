Interest Rate Model
Interest Rate Model is a modular smart contract for on-chain interest calculation in lending protocols.
It adjusts borrowing and lending rates dynamically based on pool utilization, ensuring balance between borrowers and lenders in decentralized financial systems.

Features
Dynamic interest rates based on utilization
Configurable parameters (base, slopes, optimal point)
Borrow and supply rate calculations
Governance-controlled parameter updates
Composable with lending, staking, or stablecoin modules

Technical Overview
Language: Clarity
Key Parameters:
Parameter	Description	Example
base-rate	Minimum interest rate	2%
slope1	Rate increase before optimal utilization	10%
slope2	Rate increase beyond optimal utilization	50%
optimal-utilization	Ideal pool usage threshold	80%
Core Functions:
get-utilization(total-supplied, total-borrowed)
get-borrow-rate(total-supplied, total-borrowed)
get-supply-rate(total-supplied, total-borrowed, reserve-factor)
update-params(base, slope1, slope2, optimal)

Example Calculation
Let:
Total Supplied = 10,000 STX
Total Borrowed = 7,000 STX
Utilization = 70%
Base = 2%, Slope1 = 10%, Optimal = 80%
Then:
Borrow Rate = 2% + (10% * 70 / 80) = 10.75%
Supply Rate = Borrow Rate * Utilization * (1 - reserve-factor)
