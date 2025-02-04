{-# LANGUAGE DataKinds #-}
{-
---
fulltitle: GADTs
date: October 16, 2023
---
-}
{-# LANGUAGE GADTs #-}

{-
Today we are going to talk about two of my favorite GHC extensions.
-}

module GADTs where

import Data.Kind (Type)
import Test.HUnit (Test, (~?=))

{-
\*Generalized Algebraic Datatypes*, or GADTs, are one of GHC's more unusual
extensions to Haskell.  In this module, we'll introduce GADTs and related
features of GHC's type system.

An Untyped Expression Evaluator
-------------------------------

As a motivating example, here is a standard datatype of integer and boolean
expressions. You might use this datatype if you were defining a simple
programming language, such as the formula evaluator in a spreadsheet.
-}

data OExp
  = OInt Int -- a number constant, like '2'
  | OBool Bool -- a boolean constant, like 'true'
  | OAdd OExp OExp -- add two expressions, like 'e1 + e2'
  | OIsZero OExp -- test if an expression is zero
  | OIf OExp OExp OExp -- if expression, 'if e1 then e2 else e3'
  deriving (Eq, Show)

{-
Here are some example expressions.
-}

-- The expression "1 + 3"
oe1 :: OExp
oe1 = OAdd (OInt 1) (OInt 3)

-- The expression "if (3 + -3) == 0 then 3 else 4"
oe2 :: OExp
oe2 = OIf (OIsZero (OAdd (OInt 3) (OInt (-3)))) (OInt 3) (OInt 4)

{-
And here is an evaluator for these expressions. Note that the result type of
this interpreter could either be a boolean or an integer value.
-}

oevaluate :: OExp -> Maybe (Either Int Bool)
oevaluate = go
  where
    go (OInt i) = Just (Left i)
    go (OBool b) = Just (Right b)
    go (OAdd e1 e2) =
      case (go e1, go e2) of
        (Just (Left i1), Just (Left i2)) -> Just (Left (i1 + i2))
        _ -> Nothing
    go (OIsZero e1) =
      case go e1 of
        Just (Left i) -> Just (Right (i == 0))
        Just (Right b1) -> Nothing
        Nothing -> Nothing
    go (OIf e1 e2 e3) =
      case go e1 of
        Just (Right b) -> if b then go e1 else go e2
        _ -> Nothing

{-
Ugh. That Maybe/Either combination is awkward.
这边有两个问题，第一个问题是我们似乎需要同一个函数返回两种不同的类型
另一个问题是，我们似乎不希望某些类型参与运算，比如我们不想让整数和bool相加
-}

-- >>> oevaluate oe1
-- Just (Left 4)

-- >>> oevaluate oe2
-- Just (Left 3)

{-
Plus, this language admits some strange terms:
-}

-- "True + 1"
bad_oe1 :: OExp
bad_oe1 = OAdd (OBool True) (OInt 1)

-- "if 1 then True else 3"
bad_oe2 :: OExp
bad_oe2 = OIf (OInt 1) (OBool True) (OInt 3)

-- >>> oevaluate bad_oe1
-- Nothing

-- >>> oevaluate bad_oe2
-- Just (Left 3)

{-
A Typed Expression Evaluator
----------------------------

As a first step, let's rewrite the definition of the expression
datatype in so-called "GADT syntax":
-}

data SExp where
  SInt :: Int -> SExp
  SBool :: Bool -> SExp
  SAdd :: SExp -> SExp -> SExp
  SIsZero :: SExp -> SExp
  SIf :: SExp -> SExp -> SExp -> SExp

{-
We haven't changed anything yet -- this version means exactly the same as the
definition above.  The change of syntax makes the types of the constructors --
in particular, their result type -- more explicit in their declarations.  Note
that, here, the result type of every constructor is `SExp`, and this makes
sense because they all belong to the `SExp` datatype.

Now let's refine it:
-}

data GExp :: Type -> Type where
  GInt :: Int -> GExp Int
  GBool :: Bool -> GExp Bool
  GAdd :: GExp Int -> GExp Int -> GExp Int
  GIsZero :: GExp Int -> GExp Bool
  GIf :: GExp Bool -> GExp a -> GExp a -> GExp a

{-
Note what's happened: every constructor still returns some kind of
`GExp`, but the type parameter to `GExp` is sometimes refined to
something more specific than `a`.
-}

-- "1 + 3 == 0"
ge1 :: GExp Bool
ge1 = GIsZero (GAdd (GInt 1) (GInt 3))

-- "if True then 3 else 4"
ge2 :: GExp Int
ge2 = GIf (GBool True) (GInt 3) (GInt 4)

{-
Check out the type errors that result if you uncomment these expressions.
-}

-- bad_ge1 :: GExp Int
-- bad_ge1 = GAdd (GBool True) (GInt 1)

-- bad_ge2 :: GExp Int
-- bad_ge2 = GIf (GInt 1) (GBool True) (GInt 3)

-- bad_ge3 :: GExp Int
-- bad_ge3 = GIf (GBool True) (GInt 1) (GBool True)

{-
Now we can give our evaluator a more exact type and write it in a much
clearer way:
-}

evaluate :: forall t. GExp t -> t
evaluate = go
  where
    go :: forall t. GExp t -> t
    go (GInt i) = i
    go (GBool b) = b
    go (GAdd e1 e2) = go e1 + go e2
    go (GIsZero e1) = go e1 == 0
    go (GIf e1 e2 e3) = if go e1 then go e2 else go e3

{-
Not only that, our evaluator is more efficient [1] because it does not need to
wrap the result in the `Maybe` and `Either` datatypes.

GADTs with DataKinds
--------------------

Let's look at one more simple example, which also motivates another
GHC extension that is often useful with GADTs.

We have seen that **kinds** describe _types_, just like **types**
describe _terms_. For example, the parameter to `T` below must have
the kind of types with one parameter, written `Type -> Type`.
In other words, `a` must be like `Maybe` or `[]`.

We can write this kind right before our type definition.
-}

type T :: (Type -> Type) -> Type
-- data T a = MkT (a Int)
data T a where
  MkT :: (a Int) -> T a

{-
The `DataKinds` extension of GHC allows us to use _datatypes_ as kinds.
For example, this _type_, `U` is parameterized by a boolean.
-}

type U :: Bool -> Type
data U a = MkU

{-
That means that the kind of `U` is `Bool -> Type`.  In other words, both `U 'True` [2]
and `U 'False` are valid types for `MkU` (and different from each other).
-}

exUT :: U 'True
exUT = MkU

exUF :: U 'False
exUF = MkU

-- This line doesn't type check because (==) requires arguments with the same types.
-- exEQ = exUT == exUF

{-
Right now, `U` doesn't seem very useful as it doesn't tell us very much.
So let's look at a more informative GADTs.

Consider a version of lists where the flag indicates whether the list is
empty or not. To keep track, let's define a flag for this purpose...
-}

data Flag = Empty | NonEmpty

{-
...and then use it to give a more refined definition of
lists.

As we saw above, GADTs allow the result type of data constructors to
vary. In this case, we can give `Nil` a type that statically declares
that the list is empty.
-}

data List :: Flag -> Type -> Type where
  Nil :: List 'Empty a
  Cons :: a -> List f a -> List 'NonEmpty a

deriving instance (Show a) => Show (List f a)

{-
Analogously, the type of `Cons` reflects that it creates a
nonempty list. Note that the second argument of `Cons` can have
either flag -- it could be an empty or nonempty list.

Note, too, that in the type `List 'Empty a`, the _type_ `Flag` has been lifted
to a _kind_ (i.e., it is allowed to participate in the kind expression `Flag
-> Type -> Type`), and the _value_ constructor `Empty` is now allowed to appear in
the _type_ expression `List Empty a`.

(What we're seeing is a simple form of _dependent types_, where values
are allowed to appear at the type level.)
-}

{-
  仅仅通过查看数据的“类型”，即 type，就可以知道这个list是不是空
  也就是说对于那些必须接受非空列表运算的函数，也许可以在 compile time
  就发现问题。

  注意：

  ex2 :: forall f. List f Int
  ex2 = Nil

  会有compile time error
  但是

  ex3 :: exits f. List f Int
  ex3 = Nil

  也许可以。但是 Haskell 并没有这个 feature

  如果我们想表达：我们不知道具体是哪个flag但是肯定有一个flag的值
  可以查看 OldList
-}

ex0 :: List 'Empty Int
ex0 = Nil

ex1 :: List 'NonEmpty Int
ex1 = Cons 1 (Cons 2 (Cons 3 Nil))

{-
The payoff for this refinement is that, for example, the `head`
function can now require that its argument be a nonempty list. If we
try to give it an empty list, GHC will report a type error.
-}

safeHd :: List NonEmpty a -> a
safeHd (Cons h _) = h

-- >>> safeHd ex1
-- 1

-- >>> safeHd ex0

{-
(In fact, including a case for `Nil` is not only not needed: it is not
allowed!)

Compare this definition to the unsafe version of head.
-}

-- unsafeHd :: [a] -> a
-- unsafeHd (x : _) = x

-- >>> unsafeHd [1,2]

-- >>> unsafeHd []

{-
This `Empty`/`NonEmpty` flag doesn't interact much with some of the list
functions. For example, `foldr` works for both empty and nonempty lists.
-}

foldr' :: (a -> b -> b) -> b -> List f a -> b
foldr' _ b Nil = b
foldr' f b (Cons x xs) = f x (foldr' f b xs)

{-
But the `foldr1` variant (which assumes that the list is nonempty and
omits the "base" argument) can now _require_ that its argument be
nonempty.
-}

foldr1' :: (a -> a -> a) -> List NonEmpty a -> a
foldr1' _ (Cons x Nil) = x
foldr1' f (Cons x (Cons y ys)) = f x (foldr1' f (Cons y ys))

{-
The type of `map` becomes stronger in an interesting way: It says that
we take empty lists to empty lists and nonempty lists to nonempty
lists. If we forgot the `Cons` in the last line, the function wouldn't
type check. (Though, sadly, it would still type check if we had two
`Cons`es instead of one.)
-}

{-
下面的代码会 type check，因为函数的 type 并不禁止这种 implementation
但是这种实现对于下面的 map’ 行不通，因为从 type 层面就禁止了
-- mapBad :: (a -> b) -> [a] -> [b]
-- mapBad f xs = []

  神奇的是下面这个实现也被禁止了，因为你不知道 xs 是不是空，所以也就不知道 map' f xs
  是不是空。我们必须保证第二个case的结果在 compile time 是非空
-- mapBad' :: (a -> b) -> List f a -> List f a
-- mapBad' f Nil = Nil
-- mapBad' f (Cons x xs) = map' f xs

  只是提一嘴，我们甚至可以把列表的长度 builtin 进 type里面，以此来避免下面的实现：
map' :: (a -> b) -> List f a -> List f b
map' f Nil = Nil
map' f (Cons x xs) = Cons (f x) (Cons (f x) (map' f xs))
-}

map' :: (a -> b) -> List f a -> List f b
map' f Nil = Nil
map' f (Cons x xs) = Cons (f x) (map' f xs)

{-
For `filter`, we don't know whether the output list will be empty or
nonempty.  (Even if the input list is nonempty, the boolean test might
fail for all elements.)  So this type doesn't work:
-}

-- filter' :: (a -> Bool) -> List f a -> List f a

{-
(Try to implement the filter function and see where you get stuck!)

This type also doesn't work...
-}

-- filter' :: (a -> Bool) -> List f a -> List f' a

{-
... because `f'` here is unconstrained, i.e., this type says that
`filter'` will return *any* `f'`. But that is not true: it will return
only one `f'` for a given input list -- we just don't know what it is!

The solution is to hide the size flag in an auxiliary datatype
-}

data OldList :: Type -> Type where
  OL :: List f a -> OldList a

deriving instance (Show a) => Show (OldList a)

toList :: OldList a -> [a]
toList (OL Nil) = []
toList (OL (Cons x xs)) = x : toList (OL xs)

{-
To go in the other direction -- from `OldList` to `List` -- we just
use pattern matching.  For example:
-}

myOldList1 :: OldList Int
myOldList1 = OL Nil

myOldList2 :: OldList Int
myOldList2 = OL (Cons 1 Nil)

isNonempty :: OldList a -> Maybe (List NonEmpty a)
isNonempty (OL Nil) = Nothing
isNonempty (OL (Cons x xs)) = Just (Cons x xs)

-- 下面这个定义却行不通
-- isNonempty' :: OldList a -> List f a
-- isNonempty' (OL l) = l

{-
Now we can use `OldList` as the result of `filter'`, with a bit of
additional pattern matching.
-}

filter' :: (a -> Bool) -> List f a -> OldList a
filter' f Nil = OL Nil
filter' f (Cons x Nil) = if f x then OL (Cons x Nil) else OL Nil
filter' f (Cons x (Cons y ys)) = if f x then OL (Cons x (Cons y ys)) else OL (Cons y ys)

filter'' :: (a -> Bool) -> List f a -> OldList a
filter'' f Nil = OL Nil
filter'' f (Cons x xs) = if f x then
  case filter'' f xs of
    OL xs' -> OL (Cons x xs')
  else filter'' f xs


-- >>> filter' (== 2) (Cons 1 (Cons 2 (Cons 3 Nil)))
-- OL (Cons 2 Nil)

{-
Although these examples are simple, GADTs and DataKinds can also work in much
larger libraries, especially to simulate the effect of *dependent types* [3].

Lecture notes
-------------

[1] The OCaml language also includes GADTs. See this [blog
post](https://blog.janestreet.com/why-gadts-matter-for-performance/) about how
Jane Street uses them to optimize their code.

[2] When data constructors are used in types, we often add a `'` in front of
them. This mark tells GHC that it should be looking for a data constructor
(like `True`) instead of a type constructor (like `Bool`). GHC won't complain
if you leave this tick off as long as there is no overloading of data
constructor and type constructor names. However, consider `[]`, and `()`, and
`(,)`. These all stand for both data constructors (i.e. the empty list, the
unit value, and the pairing constructor) and type constructors (i.e. the list
type constructor, the unit type, and the pairing type constructor). So if you
are using these to index GADTS, you must always use a tick when you mean the
data constructor.

[3] [Galois](https://galois.com/), a Haskell-based company, makes heavy use of
these features in their code base and has written up a
[short paper](http://www.davidchristiansen.dk/pubs/dependent-haskell-experience-report.pdf)
about their experiences.

-}
