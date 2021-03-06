using ThreeQ

function bruteforce(A, b)
	x = Array(Int, size(A, 2))
	bestx = similar(x)
	minnorm = Inf
	for i = 0:2 ^ length(x) - 1
		for j = 1:length(x)
			x[j] = parse(Int, bits(i)[end - j + 1])
		end
		newnorm = norm(A * x - b)
		if newnorm < minnorm
			minnorm = newnorm
			bestx = copy(x)
		end
	end
	return bestx, minnorm
end

#solve A*x=b using Denny's method where you represent x as sum(q_i * y[:, i]) where the y[:, i] are a fixed set of vectors
function denlin(A, b, y; eqscalingval=1 / 8)
	Ay = A * y
	solutions, energies, trueenergies, occurrences = binlin(Ay, b; eqscalingval=eqscalingval)
	bestindex = 0
	minnorm = Inf
	for i = 1:length(solutions)
		thisnorm = norm(Ay * solutions[i] - b)
		if thisnorm < minnorm
			minnorm = thisnorm
			bestindex = i
		end
	end
	return y * solutions[bestindex]
end

#solve the equation A*x=b where x is a binary vector
function binlin(A, b; eqscalingval=1 / 8, numreads=1000)
	model = ThreeQ.Model("binlin_model", "laptop", "c4-sw_sample", "binlin", "c4")
	#model = ThreeQ.Model("binlin_model", "online", "DW2X_SYS4", "binlin", "asdf")
	@defparam model eqscaling
	@defvar model x[1:size(A, 2)]
	#set up each equation
	quboa = zeros(size(A, 2))
	qubob = zeros(size(A, 2), size(A, 2))
	for i = 1:length(b)
		for j = 1:size(A, 2)
			quboa[j] += A[i, j] * (A[i, j] - 2 * b[i])
			for k = 1:j - 1
				qubob[j, k] += 2 * A[i, j] * A[i, k]
			end
		end
	end
	for i = 1:length(quboa)
		if quboa[i] != 0
			@addterm model eqscaling * quboa[i] * x[i]
		end
		for j = 1:length(quboa)
			if qubob[i, j] != 0
				@addterm model eqscaling * qubob[i, j] * x[i] * x[j]
			end
		end
	end
	#solve the system
	ThreeQ.solve!(model; eqscaling=eqscalingval, param_chain=1, numreads=numreads, doembed=true)
	#load the solutions
	i = 1
	solutions = Array{Float64, 1}[]
	energies = Float64[]
	trueenergies = Float64[]
	occurrences = Float64[]
	numsolutions = ThreeQ.getnumsolutions(model)
	for i = 1:numsolutions
		@loadsolution model energy occurrencesi valid i
		push!(solutions, copy(x.value))
		push!(energies, energy)
		trueenergy = norm(A * x.value - b) ^ 2
		push!(trueenergies, trueenergy)
		push!(occurrences, occurrencesi)
	end
	return solutions, energies, trueenergies, occurrences, model
end

function setup_random(N)
	#=
	A = randn(N, N)
	b = randn(N)
	=#
	A = rand(N, N) / N
	b = rand(N)
	return A, b
end
function setup_sparse_random(N, p)
	A = sprandn(N, N, p) + spdiagm(randn(N))
	b = randn(N)
	return A, b
end
function setup_laplacian(N)
	A = zeros(N, N); for i = 1:N A[i, i] = -2; end; for i = 1:N-1 A[i, i + 1] = 1; A[i + 1, i] = 1; end;
	b = -ones(N)
	return A, b
end
function setup_laplacian_lu_lower(N)
	A, b = setup_laplacian(N)
	return lu(A)[1], b
end
function setup_twobit_laplacian(N)
	A = zeros(N, 2 * N)
	b = -.75 * ones(N)
	bit1value = 2
	bit0value = 1
	A[1, 1] = -2 * bit1value
	A[1, 2] = -2 * bit0value
	A[1, 3] = 1 * bit1value
	A[1, 4] = 1 * bit0value
	A[end, end - 3] = 1 * bit1value
	A[end, end - 2] = 1 * bit0value
	A[end, end - 1] = -2 * bit1value
	A[end, end] = -2 * bit0value
	for i = 2:N - 1
		A[i, 2 * i - 3] = 1 * bit1value
		A[i, 2 * i - 2] = 1 * bit0value
		A[i, 2 * i - 1] = -2 * bit1value
		A[i, 2 * i] = -2 * bit0value
		A[i, 2 * i + 1] = 1 * bit1value
		A[i, 2 * i + 2] = 1 * bit0value
	end
	return A, b
end
function setup_nbit_laplacian(N, n)
	A = zeros(N, n * N)
	bitvals = [2. ^ -i for i = 1:n]
	for i = 1:n
		A[1, i] = -2 * bitvals[i]
		A[1, n + i] = 1 * bitvals[i]
		A[end, end - 2 * n + i] = 1 * bitvals[i]
		A[end, end - n + i] = -2 * bitvals[i]
	end
	for i = 2:N - 1
		for j = 1:n
			A[i, n * i - 2 * n + j] = 1 * bitvals[j]
			A[i, n * i - n + j] = -2 * bitvals[j]
			A[i, n * i + j] = 1 * bitvals[j]
		end
	end
	#x = bitrand(n * N)
	x = zeros(n * N)
	for i = 1:N
		x[(i - 1) * n + 1] = 1
	end
	@show x
	b = A * x
	return A, b
end
srand(0)
N = 3
numreads = 10 ^ 4
#A, b = setup_random(N); eqscalingval = 1 / N
#A, b = setup_sparse_random(N, .25); eqscalingval = 1 / 8
#A, b = setup_laplacian(N); eqscalingval = 1 / N ^ .75
#A, b = setup_laplacian_lu_lower(N); eqscalingval = 1.
#A, b = setup_twobit_laplacian(N); eqscalingval = 1 / 32
#A, b = setup_nbit_laplacian(N, 3); eqscalingval = .005
A, b = setup_nbit_laplacian(N, 4); eqscalingval = 1e-4
@time solutions, energies, trueenergies, occurrences, model = binlin(A, b; eqscalingval=eqscalingval, numreads=numreads)#solve it with dwave
bestx, minnorm = bruteforce(A, b)#solve it by brute force
@show solutions[1]
@show bestx

#print the solutions
validcount = 0
for i = reverse(1:length(energies))
	isvalid = norm(solutions[i] - bestx) == 0
	if isvalid
		validcount += occurrences[i]
	end
	if isvalid || i == 1 || i == 2
		println("Solution #$i (valid = $isvalid)")
		println("Energy: $(energies[i])")
		println("Occurrences: $(occurrences[i])")
		println("Solution:\n$(map(x->round(Int, x), solutions[i]))")
		println("norm(A*x-b): $(norm(A * solutions[i] - b))")
		println()
	end
end
@show validcount / numreads
#@show bestx, minnorm
println("bestx:\n$bestx")
println("minnorm:\n$minnorm")
#=
for i = 1:length(energies) - 1
	@assert trueenergies[i] <= trueenergies[i + 1]#make sure the objective function is set up correctly
end
=#
