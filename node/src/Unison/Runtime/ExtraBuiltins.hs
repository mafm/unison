{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE PatternSynonyms #-}
module Unison.Runtime.ExtraBuiltins where

import Control.Concurrent.STM (atomically)
import Data.ByteString (ByteString)
import Unison.BlockStore (Series(..), BlockStore)
import Unison.Node.Builtin
import Unison.Parsers (unsafeParseType)
import Unison.Type (Type)
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import qualified Unison.Cryptography as C
import qualified Unison.Eval.Interpreter as I
import qualified Unison.Note as Note
import qualified Unison.Reference as R
import qualified Unison.Runtime.Html as Html
import qualified Unison.Runtime.Http as Http
import qualified Unison.Runtime.Index as Index
import qualified Unison.Runtime.ResourcePool as RP
import qualified Unison.SerializationAndHashing as SAH
import qualified Unison.Term as Term
import qualified Unison.Type as Type

indexT :: Ord v => Type v -> Type v -> Type v
indexT k v = Type.ref (R.Builtin "Index") `Type.app` k `Type.app` v

index :: Term.Term V -> Term.Term V
index h = Term.ref (R.Builtin "Index") `Term.app` h

linkT :: Ord v => Type v
linkT = Type.ref (R.Builtin "Link")

link :: Term.Term V -> Term.Term V -> Term.Term V
link href description = Term.ref (R.Builtin "Link") `Term.app` href `Term.app` description

linkToTerm :: Html.Link -> Term.Term V
linkToTerm (Html.Link href description) = link (Term.lit $ Term.Text href)
  (Term.lit $ Term.Text description)

pattern Index' s <- Term.App'
                    (Term.Ref' (R.Builtin "Index"))
                    (Term.Text' s)

pattern Link' href description <-
  Term.App' (Term.App' (Term.Ref' (R.Builtin "Link"))
                       (Term.Text' href))
  (Term.Text' description)

-- TODO rewrite builtins not to use unsafe code
makeAPI :: Eq a => BlockStore a -> C.Cryptography k syk sk skp s h ByteString
  -> IO (WHNFEval -> [Builtin])
makeAPI blockStore crypto = do
  let nextID = do
        cp <- C.randomBytes crypto 64
        ud <- C.randomBytes crypto 64
        pure (Series cp, Series ud)
  resourcePool <- RP.make 3 10 (Index.loadEncrypted blockStore crypto) Index.flush
  pure (\whnf -> map (\(r, o, t, m) -> Builtin r o t m)
     [ let r = R.Builtin "Index.unsafeEmpty"
           op [] = Note.lift $ do
             ident <- nextID
             pure . index . Term.lit . Term.Text . Index.idToText $ ident
           op _ = fail "Index.unsafeEmpty unpossible"
           type' = unsafeParseType "forall k v. Store k v"
       in (r, Just (I.Primop 0 op), type', prefix "unsafeEmpty")
     , let r = R.Builtin "Index.empty"
           op [] = pure $
             Term.builtin "Remote.pure" `Term.app` Term.builtin "Index.unsafeEmpty"
           op _ = fail "Index.empty unpossible"
           type' = unsafeParseType "forall k v. Remote (Store k v)"
       in (r, Just (I.Primop 0 op), type', prefix "empty")
     , let r = R.Builtin "Index.unsafeLookup"
           op [indexToken, key] = inject g indexToken key where
             inject g indexToken key = do
               i <- whnf indexToken
               k <- whnf key
               g i k
             g (Index' h) k = do
               val <- Note.lift $ do
                 (db, _) <- RP.acquire resourcePool . Index.textToId $ h
                 result <- atomically $ Index.lookup (SAH.hash' k) db
                 case result >>= (pure . SAH.deserializeTermFromBytes . snd) of
                   Just (Left s) -> fail ("Index.unsafeLookup could not deserialize: " ++ s)
                   Just (Right t) -> pure $ some t
                   Nothing -> pure none
               pure val
             g s k = pure $ Term.ref r `Term.app` s `Term.app` k
           op _ = fail "Index.unsafeLookup unpossible"
           type' = unsafeParseType "forall k v. k -> Store k v -> Option v"
       in (r, Just (I.Primop 2 op), type', prefix "unsafeLookup")
     , let r = R.Builtin "Index.lookup"
           op [indexToken, key] = pure $ Term.builtin "Remote.pure" `Term.app`
             (Term.builtin "Index.unsafeLookup" `Term.app` indexToken `Term.app` key)
           op _ = fail "Index.lookup unpossible"
           type' = unsafeParseType "forall k v. k -> Store k v -> Remote (Option v)"
       in (r, Just (I.Primop 2 op), type', prefix "lookup")
     , let r = R.Builtin "Index.unsafeInsert"
           op [k, v, store] = inject g k v store where
             inject g k v store = do
               k' <- whnf k
               v' <- whnf v
               s <- whnf store
               g k' v' s
             g k v (Index' h) = do
               Note.lift $ do
                 (db, _) <- RP.acquire resourcePool . Index.textToId $ h
                 atomically
                   (Index.insert (SAH.hash' k) (SAH.serializeTerm k, SAH.serializeTerm v) db)
                   >>= atomically
               pure unitRef
             g k v store = pure $ Term.ref r `Term.app` k `Term.app` v `Term.app` store
           op _ = fail "Index.unsafeInsert unpossible"
           type' = unsafeParseType "forall k v. k -> v -> Store k v -> Unit"
       in (r, Just (I.Primop 3 op), type', prefix "unsafeInsert")
     , let r = R.Builtin "Index.insert"
           op [k, v, store] = pure $ Term.builtin "Remote.pure" `Term.app`
             (Term.builtin "Index.unsafeInsert" `Term.app` k `Term.app` v `Term.app` store)
           op _ = fail "Index.insert unpossible"
           type' = unsafeParseType "forall k v. k -> v -> Store k v -> Remote Unit"
       in (r, Just (I.Primop 3 op), type', prefix "insert")
     , let r = R.Builtin "Html.getLinks"
           op [html] = do
             html' <- whnf html
             pure $ case html' of
               Term.Text' h -> Term.vector' . Vector.fromList . map linkToTerm
                 $ Html.getLinks h
               x -> Term.ref r `Term.app` x
           op _ = fail "Html.getLinks unpossible"
       in (r, Just (I.Primop 1 op), unsafeParseType "Text -> Vector Link", prefix "getLinks")
     , let r = R.Builtin "Html.getHref"
           op [link] = do
             link' <- whnf link
             pure $ case link' of
               Link' href _ -> Term.lit (Term.Text href)
               x -> Term.ref r `Term.app` x
           op _ = fail "Html.getHref unpossible"
       in (r, Just (I.Primop 1 op), unsafeParseType "Link -> Text", prefix "getHref")
     , let r = R.Builtin "Html.getDescription"
           op [link] = do
             link' <- whnf link
             pure $ case link' of
               Link' _ d -> Term.lit (Term.Text d)
               x -> Term.ref r `Term.app` x
           op _ = fail "Html.getDescription unpossible"
       in (r, Just (I.Primop 1 op), unsafeParseType "Link -> Text", prefix "getDescription")
     , let r = R.Builtin "Http.unsafeGetURL"
           op [url] = do
             url <- whnf url
             case url of
               Term.Text' url -> Note.lift $ do
                   result <- Http.get $ Text.unpack url
                   pure $ case result of
                     Right x -> right $ Term.text x
                     Left x -> left . Term.text . Text.pack $ show x
               x -> pure $ Term.ref r `Term.app` x
           op _ = fail "Http.unsafeGetURL unpossible"
       in (r, Just (I.Primop 1 op), unsafeParseType "Text -> Either Text Text", prefix "unsafeGetURL")
     , let r = R.Builtin "Http.getURL"
           op [url] = pure $ Term.builtin "Remote.pure" `Term.app`
             (Term.builtin "Http.unsafeGetURL" `Term.app` url)
           op _ = fail "Http.getURL unpossible"
       in (r, Just (I.Primop 1 op), unsafeParseType "Text -> Remote (Either Text Text)", prefix "getURL")
     ])