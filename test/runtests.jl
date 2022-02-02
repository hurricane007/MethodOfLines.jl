using SafeTestsets

const GROUP = get(ENV, "GROUP", "All")
const is_APPVEYOR = Sys.iswindows() && haskey(ENV,"APPVEYOR")
const is_TRAVIS = haskey(ENV,"TRAVIS")

# Start Test Script

@time begin
    
    if GROUP == "All" || GROUP == "Component Tests"
       #@time @safetestset "Test for regression against original code" begin include("regression_test.jl") end
        @time @safetestset "MOLFiniteDifference Utils" begin include("utils_test.jl") end
        @time @safetestset "Discretization of space and grid types" begin include("components/DiscreteSpace.jl") end
        @time @safetestset "Finite Difference Schemes" begin include("components/finite_diff_schemes.jl") end
    end

    if GROUP == "All" || GROUP == "Integration Tests"
        @time @safetestset "MOLFiniteDifference Interface" begin include("pde_systems/MOLtest.jl") end
        @time @safetestset "MOLFiniteDifference Interface" begin include("pde_systems/MOLfornberg_weights.jl") end
        #@time @safetestset "MOLFiniteDifference Interface: Linear Convection" begin include("pde_systems/MOL_1D_Linear_Convection.jl") end
        @time @safetestset "MOLFiniteDifference Interface: 1D Linear Diffusion" begin include("pde_systems/MOL_1D_Linear_Diffusion.jl") end
        @time @safetestset "MOLFiniteDifference Interface: 1D Non-Linear Diffusion" begin include("pde_systems/MOL_1D_NonLinear_Diffusion.jl") end
        @time @safetestset "MOLFiniteDifference Interface: 2D Diffusion" begin include("pde_systems/MOL_2D_Diffusion.jl") end
        @time @safetestset "MOLFiniteDifference Interface: 1D HigherOrder" begin include("pde_systems/MOL_1D_HigherOrder.jl") end
        @time @safetestset "MOLFiniteDifference Interface: 1D Partial DAE" begin include("pde_systems/MOL_1D_PDAE.jl") end
        @time @safetestset "MOLFiniteDifference Interface: Stationary Nonlinear Problems" begin include("pde_systems/MOL_NonlinearProblem.jl") end
    end

end