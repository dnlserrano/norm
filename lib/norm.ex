defmodule Norm do
  @moduledoc """
  Norm is a system for specifying the structure of data. It can be used for
  validation and for generation of data. Norm does not provide any set of
  predicates and instead allows you to re-use any of your existing
  validations.

  ```elixir
  import Norm

  conform!(123, spec(is_integer() and &(& > 0)))
  => 123

  conform!(-50, spec(is_integer() and &(&1 > 0)))
  ** (Norm.MismatchError) val: -50 fails: &(&1 > 0)
      (norm) lib/norm.ex:44: Norm.conform!/2

  user_schema = schema(%{
    user: schema(%{
      name: spec(is_binary()),
      age: spec(is_integer() and &(&1 > 0))
    })
  })
  conform!(%{user: %{name: "chris", age: 30}}, user_schema)
  => %{user: %{name: "chris", age: 30}}

  user_schema
  |> gen()
  |> Enum.take(3)
  => [
    %{user: %{age: 0, name: ""}},
    %{user: %{age: 2, name: "x"}},
    %{user: %{age: -2, name: ""}}
  ]
  ```

  ## Validation and conforming values

  Norm validates data by "conforming" the value to a specification. If the
  values don't conform then a list of errors is returned. There are
  2 functions provided for this `conform/2` and `conform!/2`. If you need to
  return a list of well defined errors then you should use `conform/2`.
  Otherwise `conform!/2` is generally more useful. The input data is
  always passed as the 1st argument to `conform` so that calls to conform
  are easily chainable.

  ### Predicates and specs

  Norm does not provide a special set of predicates and instead allows you
  to convert any predicate into a spec with the `spec/1` macro. Predicates
  can be composed together using the `and` and `or` keywords. You can also
  use anonymous functions to create specs.

  ```elixir
  spec(is_binary())
  spec(is_integer() and &(&1 > 0))
  spec(is_binary() and fn str -> String.length(str) > 0 end)
  ```

  The data is always passed as the first argument to your predicate so you
  can use predicates with multiple values like so:

  ```elixir
  def greater?(x, y), do: x > y
  conform!(10, spec(greater?(5)))
  => 10
  conform!(3, spec(greater?(5)))
  ** (Norm.MismatchError) val: 3 fails: greater?(5)
      (norm) lib/norm.ex:44: Norm.conform!/2
  ```

  ### Schemas

  Norm provides a `schema/1` function for specifying maps and structs:

  ```elixir
  user_schema = schema(%{
    user: schema(%{
      name: spec(is_binary()),
      age: spec(is_integer()),
    })
  })

  conform!(%{user: %{name: "chris", age: 31}}, user_schema)
  => %{user: %{name: "chris", age: 31}}

  conform!(%{user: %{name: "chris", age: -31}}, user_schema)
  ** (Norm.MismatchError) in: :user/:age val: -31 fails: &(&1 > 0)
      (norm) lib/norm.ex:44: Norm.conform!/2
  ```

  You can also create specs from structs:

  ```elixir
  defmodule User do
    defstruct [:name, :age]

    def s, do: schema(%__MODULE__{
        name: spec(is_binary()),
        age: spec(is_integer())
      }
  end
  ```

  This will ensure that the input is a `User` struct with the key that match
  the given specification. Its convention to provide a `s()` function in the
  module that defines the struct so that schema's can be shared throughout
  your system.

  You don't need to provide specs for all the keys in your struct. Only the
  specced keys will be conformed. The remaining keys will be checked for
  presence.

  ```elixir
  defmodule User do
    defstruct [:name, :age]
  end

  conform!(%User{name: "chris"}, schema(%User{}))
  => %User{name: "chris", age: nil}
  ```

  #### Key semantics

  Atom and string keys are matched explicitly and there is no casting that
  occurs when conforming values. If you need to match on string keys you
  should specify your schema with string keys.

  Schema's expect the exact set of keys specified. Passing unspecified keys
  to a schema is considered an error. This inhibits a schema's ability to
  grow. You may need to do this but generally you'll want to create
  a "selection" of the schema in order to allow for schema growth over time.

  ### Selections

  You may have noticed that there's no way to specify optional keys in
  a schema. This may seem like an oversite but its actually an intentional
  design decision. Whether a key should be present in a schema is determined
  by the call site and not by the schema itself. For instance think about
  the assigns in a plug conn. When are the assigns optional? It depends on
  where you are in the pipeline.

  Schema's also force all keys to match at all times. This is generally
  useful as it limits your ability to introduce errors. But it also limits
  schema growth and turns changes that should be non-breaking into breaking
  changes.

  In order to support both of these scenarios Norm provides the
  `selection/2` function. `selection/2` allows you to specify exactly the
  keys you require from a schema at the place where you require them.

  ```elixir
  user_schema = schema(%{
    user: schema(%{
      name: spec(is_binary()),
      age: spec(is_integer()),
    })
  })
  just_age = selection(user_schema, [user: [:age]])

  conform!(%{user: %{name: "chris", age: 31}}, just_age)
  => %{user: %{age: 31}}

  # Selection also disregards unspecified keys
  conform!(%{user: %{name: "chris", age: 31, unspecified: nil}, other_stuff: :foo}, just_age)
  => %{user: %{age: 31}}
  ```

  ### Patterns

  Norm provides a way to specify alternative specs using the `alt/1`
  function. This is useful when you need to support multiple schema's or
  multiple alternative specs.

  ```elixir
  create_event = schema(%{type: spec(&(&1 == :create))})
  update_event = schema(%{type: spec(&(&1 == :update))})
  event = alt(create: create_event, update: update_event)

  conform!(%{type: :create}, event)
  => {:create, %{type: :create}}

  conform!(%{type: :update}, event)
  => {:update, %{type: :update}}

  conform!(%{type: :delete}, event)
  ** (Norm.MismatchError)
    in: :create/:type val: :delete fails: &(&1 == :create)
    in: :update/:type val: :delete fails: &(&1 == :update)
  ```

  ## Generators

  Along with validating that data conforms to a given specification, Norm
  can also use specificiations to generate examples of good data. These
  examples can then be used for property based testing, local development,
  seeding databases, or any other usecase.

  ```elixir
  user_schema = schema(%{
    user: schema(%{
      name: spec(is_binary()),
      age: spec(is_integer() and &(&1 > 0))
    })
  })
  conform!(%{user: %{name: "chris", age: 30}}, user_schema)
  => %{user: %{name: "chris", age: 30}}

  user_schema
  |> gen()
  |> Enum.take(3)
  => [
    %{user: %{age: 0, name: ""}},
    %{user: %{age: 2, name: "x"}},
    %{user: %{age: -2, name: ""}}
  ]
  ```

  Under the hood Norm uses StreamData for its data generation. This means
  you can use your specs in tests like so:

  ```elixir
  input_data = schema(%{"user" => schema(%{"name" => spec(is_binary())})})

  property "users can update names" do
    check all input <- gen(input_data) do
      assert :ok == update_user(input)
    end
  end
  ```

  ### Built in generators

  Norm will try to infer the generator to use from the predicate defined in
  `spec`. It looks specifically for the guard clauses used for primitive
  types in elixir. Not all of the built in guard clauses are supported yet.
  PRs are very welcome ;).

  ### Guiding generators

  You may have specs like `spec(fn x -> rem(x, 2) == 0 end)` which check to
  see that an integer is even or not. This generator expects integer values
  but there's no way for Norm to determine this. If you try to create
  a generator from this spec you'll get an error:

  ```elixir
  gen(spec(fn x -> rem(x, 2) == 0 end))
  ** (Norm.GeneratorError) Unable to create a generator for: fn x -> rem(x, 2) == 0 end
      (norm) lib/norm.ex:76: Norm.gen/1
  ```

  You can guide Norm to the right generator by specifying a guard clause as
  the first predicate in a spec. If Norm can find the right generator then
  it will use any other predicates as filters in the generator.

  ```elixir
  Enum.take(gen(spec(is_integer() and fn x -> rem(x, 2) == 0 end)), 5)
  [0, -2, 2, 0, 4]
  ```

  But its also possible to create filters that are too specific such as
  this:

  ```elixir
  gen(spec(is_binary() and &(&1 =~ ~r/foobarbaz/)))
  ```

  Norm can determine the generators to use however its incredibly unlikely
  that Norm will be able to generate data that matches the filter. After 25
  consequtive unseccesful attempts to generate a good value Norm (StreamData
  under the hood) will return an error. In these scenarios we can create
  a custom generator.

  ### Overriding generators

  You'll often need to guide your generators into the interesting parts of the
  state space so that you can easily find bugs. That means you'll want to tweak
  and control your generators. Norm provides an escape hatch for creating your
  own generators with the `with_gen/2` function:

  ```elixir
  age = spec(is_integer() and &(&1 >= 0))
  reasonable_ages = with_gen(age, StreamData.integer(0..105))
  ```

  Because `gen/1` returns a StreamData generator you can compose your generators
  with other StreamData functions:

  ```elixir
  age = spec(is_integer() and &(&1 >= 0))
  StreamData.frequencies([
    {3, gen(age)},
    {1, StreamData.binary()},
  ])

  gen(age) |> StreamData.map(&Integer.to_string/1) |> Enum.take(5)
  ["1", "1", "3", "4", "1"]
  ```

  This allows you to compose generators however you need to while keeping your
  generation co-located with the specification of the data.
  """

  alias Norm.Conformer
  alias Norm.Generatable
  alias Norm.Generator
  alias Norm.Spec
  alias Norm.Spec.{
    Alt,
    Selection,
  }
  alias Norm.Schema
  alias Norm.MismatchError
  alias Norm.GeneratorError

  @doc ~S"""
  Verifies that the payload conforms to the specification. A "success tuple"
  is returned that contains either the conformed value or the error explanation.

  ## Examples:

      iex> conform(42, spec(is_integer()))
      {:ok, 42}
      iex> conform(42, spec(fn x -> x == 42 end))
      {:ok, 42}
      iex> conform(42, spec(&(&1 >= 0)))
      {:ok, 42}
      iex> conform(42, spec(&(&1 >= 100)))
      {:error, ["val: 42 fails: &(&1 >= 100)"]}
      iex> conform("foo", spec(is_integer()))
      {:error, ["val: \"foo\" fails: is_integer()"]}
  """
  def conform(input, spec) do
    Conformer.conform(spec, input)
  end

  @doc ~S"""
  Returns the conformed value or raises a mismatch error.

  ## Examples

      iex> conform!(42, spec(is_integer()))
      42
      iex> conform!(42, spec(is_binary()))
      ** (Norm.MismatchError) val: 42 fails: is_binary()
  """
  def conform!(input, spec) do
    case Conformer.conform(spec, input) do
      {:ok, input} -> input
      {:error, errors} -> raise MismatchError, errors
    end
  end

  @doc ~S"""
  Checks if the value conforms to the spec and returns a boolean.

  ## Examples

      iex> valid?(42,  spec(is_integer()))
      true
      iex> valid?("foo",  spec(is_integer()))
      false
  """
  def valid?(input, spec) do
    case Conformer.conform(spec, input) do
      {:ok, _}    -> true
      {:error, _} -> false
    end
  end

  @doc ~S"""
  Creates a generator from a spec, schema, or selection.

  ## Examples

      iex> gen(spec(is_integer())) |> Enum.take(3) |> Enum.all?(&is_integer/1)
      true
      iex> gen(spec(is_binary())) |> Enum.take(3) |> Enum.all?(&is_binary/1)
      true
      iex> gen(spec(&(&1 > 0)))
      ** (Norm.GeneratorError) Unable to create a generator for: &(&1 > 0)
  """
  def gen(spec) do
    case Generatable.gen(spec) do
      {:ok, generator} -> generator
      {:error, error} -> raise GeneratorError, error
    end
  end

  @doc """
  Overwrites the default generator with a custom generator. The generator
  can be any valid StreamData generator. This means you can either use Norms
  built in `gen/1` function or you can drop into StreamData directly.

  ## Examples

      iex> Enum.take(gen(with_gen(spec(is_integer()), StreamData.constant("hello world"))), 3)
      ["hello world", "hello world", "hello world"]
  """
  def with_gen(spec, %StreamData{}=generator) do
    Generator.new(spec, generator)
  end

  @doc ~S"""
  Creates a new spec. Specs can be created from any existing predicates or
  anonymous functions. Specs must return a boolean value.

  Predicates can be arbitrarily composed using the `and` and `or` keywords.

  ## Examples:

      iex> conform!(21, spec(is_integer()))
      21
      iex> conform!(21, spec(is_integer() and &(&1 >= 21)))
      21
      iex> conform("21", spec(is_integer() and &(&1 >= 21)))
      {:error, ["val: \"21\" fails: is_integer()"]}
      iex> conform!(:foo, spec(is_atom() or is_binary()))
      :foo
      iex> conform!("foo", spec(is_atom() or is_binary()))
      "foo"
      iex> conform(21, spec(is_atom() or is_binary()))
      {:error, ["val: 21 fails: is_atom()", "val: 21 fails: is_binary()"]}
  """
  defmacro spec(predicate) do
    spec = Spec.build(predicate)

    quote do
      unquote(spec)
    end
  end

  @doc ~S"""
  Creates a re-usable schema.

  ## Examples

      iex> conform!(%{age: 31, name: "chris"},
      ...>   schema(%{age: spec(is_integer()), name: spec(is_binary())})
      ...> )
      %{age: 31, name: "chris"}
  """
  def schema(input) do
    Schema.build(input)
  end

  @doc ~S"""
  Chooses between alternative predicates or patterns. The patterns must be tagged with an atom.
  When conforming data to this specification the data is returned as a tuple with the tag.

  ## Examples

      iex> conform!("foo", alt(s: spec(is_binary()), a: spec(is_atom())))
      {:s, "foo"}
      iex> conform!(:foo, alt(s: spec(is_binary()), a: spec(is_atom())))
      {:a, :foo}
      iex> conform!(123, alt(num: spec(is_integer()), str: spec(is_binary())))
      {:num, 123}
      iex> conform!("foo", alt(num: spec(is_integer()), str: spec(is_binary())))
      {:str, "foo"}
      iex> conform(true, alt(num: spec(is_integer()), str: spec(is_binary())))
      {:error, ["in: :num val: true fails: is_integer()", "in: :str val: true fails: is_binary()"]}
  """
  def alt(specs) when is_list(specs) do
    %Alt{specs: specs}
  end

  @doc ~S"""
  Selections provide a way to allow optional keys in a schema. This allows
  schema's to be defined once and re-used in multiple scenarios.

  ## Examples

      iex> conform!(%{age: 31}, selection(schema(%{age: spec(is_integer()), name: spec(is_binary())}), [:age]))
      %{age: 31}
  """
  def selection(%Schema{}=schema, path) do
    Selection.new(schema, path)
  end

  # @doc ~S"""
  # Concatenates a sequence of predicates or patterns together. These predicates
  # must be tagged with an atom. The conformed data is returned as a
  # keyword list.

  # iex> conform!([31, "Chris"], cat(age: integer?(), name: string?()))
  # [age: 31, name: "Chris"]
  # iex> conform([true, "Chris"], cat(age: integer?(), name: string?()))
  # {:error, ["in: [0] at: :age val: true fails: integer?()"]}
  # iex> conform([31, :chris], cat(age: integer?(), name: string?()))
  # {:error, ["in: [1] at: :name val: :chris fails: string?()"]}
  # iex> conform([31], cat(age: integer?(), name: string?()))
  # {:error, ["in: [1] at: :name val: nil fails: Insufficient input"]}
  # """
  # def cat(opts) do
  #   fn path, input ->
  #     results =
  #       opts
  #       |> Enum.with_index
  #       |> Enum.map(fn {{tag, spec}, i} ->
  #         val = Enum.at(input, i)
  #         if val do
  #           {tag, spec.(path ++ [{:index, i}], val)}
  #         else
  #           {tag, {:error, [error(path ++ [{:index, i}], nil, "Insufficient input")]}}
  #         end
  #       end)

  #     errors =
  #       results
  #       |> Enum.filter(fn {_, {result, _}} -> result == :error end)
  #       |> Enum.map(fn {tag, {_, errors}} -> {tag, errors} end)
  #       |> Enum.flat_map(fn {tag, errors} -> Enum.map(errors, &(%{&1 | at: tag})) end)

  #     if Enum.any?(errors) do
  #       {:error, errors}
  #     else
  #       {:ok, Enum.map(results, fn {tag, {_, data}} -> {tag, data} end)}
  #     end
  #   end
  # end
end

