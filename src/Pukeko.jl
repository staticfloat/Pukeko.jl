# This file is a part of Pukeko.jl.
# License is MIT. https://github.com/IainNZ/Pukeko.jl

module Pukeko
    export @test, @test_throws, @parametric

    """
        TEST_PREFIX
    
    Functions with this string at the the start of their name will be treated as
    self-contained sets of tests.
    """
    const TEST_PREFIX = "test_"

    """
        TestException
    
    The `Exception`` thrown when a Pukeko test fails. Used by `run_tests` to
    distinguish between test errors and unexpected errors.
    """
    struct TestException <: Exception
        message::String
    end

    """
        test_true(value)

    Throws iff `value` is not `true`. Calls to this are generated by `@test`.
    """
    function test_true(value)
        if value != true
            throw(TestException("Expression did not evaluate to `true`: " *
                                string(value)))
        end
        return nothing
    end

    """
        test_equal(value_left, value_right)

    Test that `value_left` is equal to `value_right`. Calls to this are
    generated by `@test` for the case of `@test expr_left == expr_right`.
    """
    function test_equal(value_left, value_right)
        if value_left != value_right
            throw(TestException("Expression did not evaluate to `true`: " *
                                string(value_left) * " != " *
                                string(value_right)))
        end
        return nothing
    end

    """
        @test expression
    
    Test that `expression` is `true`.
    """
    macro test(expression)
        # If `expression` is of form `expr_left == expr_right` -> `test_equal`.
        # Otherwise, use `test_true`.
        if (expression.head == :call && expression.args[1] == :(==) &&
            length(expression.args) == 3)
            return quote
                test_equal($(esc(expression.args[2])),
                           $(esc(expression.args[3])))
            end
        end
        return quote
            test_true($(esc(expression)))
        end
    end

    @static if VERSION >= v"0.7"
        compat_name(mod) = names(mod, all=true)
    else
        compat_name(mod) = names(mod, true)
    end

    """
        run_tests(module_to_test; fail_fast=false)
    
    Runs all the sets of tests in module `module_to_test`. Test sets are defined
    as functions with names that begin with `TEST_PREFIX`. A summary is printed
    after all test sets have been run and if there were any failures an
    exception is thrown.
    
    Configuration options:

      * If `fail_fast==false` (default), if any one test function fails, the
        others will still run. If `true`, testing will stop on the first
        failure. The commandline argument `--PUKEKO_FAIL_FAST` will override
        `fail_fast` to true for all `run_tests` calls.
    """
    function run_tests(module_to_test; fail_fast=false)
        # Parse commandline arguments.
        if "--PUKEKO_FAIL_FAST" in ARGS
            fail_fast = true
        end
        # Get a clean version of module name for logging messages.
        module_name = string(module_to_test)
        if startswith(module_name, "Main.")
            module_name = module_name[6:end]
        end
        # Keep track of failures to summarize at end.
        test_failures = Dict{String, TestException}()
        test_functions = 0
        for maybe_function in compat_name(module_to_test)
            maybe_function_name = string(maybe_function)
            # If not a test function, skip to next function.
            if !startswith(maybe_function_name, TEST_PREFIX)
                continue
            end
            test_functions += 1
            # If we don't need to catch errors, don't even try.
            if fail_fast
                @eval module_to_test ($maybe_function)()
                continue
            end
            # Try to run the function. If it fails, figure out why.
            try
                @eval module_to_test ($maybe_function)()
            catch test_exception
                if isa(test_exception, TestException)
                    test_failures[maybe_function_name] = test_exception
                else
                    println("Unexpected exception occurred in test ",
                            "function `$(maybe_function_name)` ",
                            "in module `$(module_name)`")
                    throw(test_exception)
                end
            end
        end
        if length(test_failures) > 0
            println("Test failures occurred in module $(module_name)")
            println("Functions with failed tests:")
            for (function_name, test_exception) in test_failures
                println("    $(function_name): ", test_exception)
            end
            error("Some tests failed!")
        end
        println("$(test_functions) test function(s) ran successfully ",
                "in module $(module_name)")
    end

    """
        parametric(module_to_test, func, iterable)
    
    Create a version of `func` that is prefixed with `TEST_PREFIX` in
    `module_to_test` for each value in `iterable`. If a value in `iterable` is
    a tuple, it is splatted into the function arguments.
    """
    function parametric(module_to_test, func, iterable)
        for value in iterable
            func_name = Symbol(string(TEST_PREFIX, func, value))
            if value isa Tuple
                @eval module_to_test $func_name() = $func($(value)...)
            else
                @eval module_to_test $func_name() = $func($(value))
            end
        end
    end

    """
        @parametric func iterable
    
    Create a version of `func` that is prefixed with `TEST_PREFIX` in the module
    that this macro is called for each value in `iterable`. If a value in
    `iterable` is a tuple, it is splatted into the function arguments.
    """
    macro parametric(func, iterable)
        @static if VERSION >= v"0.7"
            module_ = __module__
        else
            module_ = current_module()
        end
        return quote
            parametric($(module_), $(esc(func)), $(esc(iterable)))
        end
    end
end