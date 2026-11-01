--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Shared.Packages.fusion)

-- A Fusion scope with every Fusion constructor available as a method (scope:New, scope:Computed...).
export type Scope = typeof(Fusion.scoped(Fusion))

-- A Charm signal getter, computed, atom, or any function that reads them.
export type Getter<T> = () -> T

return {}
