{-# LANGUAGE AllowAmbiguousTypes       #-}
{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE InstanceSigs              #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE PolyKinds                 #-}
{-# LANGUAGE Rank2Types                #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeOperators             #-}
{-# LANGUAGE UndecidableInstances      #-}

{-
  This module provides 2 functions to make values
  out of a registry. The general algorithm is the following

   1. for a given value type search in the existing list of values
      a value with the same type. If found return it

   2. if not found search a function having the desired output type
      if found, now try to recursively make all the input parameters.
      Keep a context of the current type trying to be built.

   3. when trying to make an input parameter if the current input type
      is already in the types trying to be built then there is a cycle.
      Throw an exception in that case

   4. when a value has been constructed place it on top of the existing value
      list so that it can be reused by other functions

-}
module Data.Registry.Make where

import           Data.Dynamic
import           Data.Registry.Internal.Make
import           Data.Registry.Internal.Registry
import           Data.Registry.Registry
import           Data.Registry.Solver
import           Data.Typeable                   (Typeable)
import qualified Prelude                         (error)
import           Protolude                       as P hiding (Constructor)
import           Type.Reflection

-- | For a given registry make an element of type a
--   We want to ensure that a is indeed one of the return types
--   We also try to statically check if there aren't other possible errors
make
  :: forall a ins out
   . (Typeable a, Contains a out, Solvable ins out)
  => Registry ins out
  -> a
make = makeUnsafe

-- | This version of make only execute checks at runtime
--   this can speed-up compilation when writing tests or in ghci
makeUnsafe :: forall a ins out . (Typeable a) => Registry ins out -> a
makeUnsafe registry =
  let values          = _values registry
      functions       = _functions registry
      specializations = _specializations registry
      modifiers       = _modifiers registry
      targetType      = someTypeRep (Proxy :: Proxy a)
  in
      -- | use the makeUntyped function to create an element of the target type from a list of values and functions
      --   the list of values is kept as some State so that newly created values can be added to the current state
      case
        evalState
          (makeUntyped targetType (Context [targetType]) functions specializations modifiers)
          values
      of
        Nothing -> Prelude.error
          ("could not create a " <> show targetType <> " out of the registry")

        Just result -> fromMaybe
          (Prelude.error ("could not cast the computed value to a " <> show targetType <> ". The value is of type: " <> show (dynTypeRep result)))
          (fromDynamic result)