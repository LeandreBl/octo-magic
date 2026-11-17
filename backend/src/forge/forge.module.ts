import { Module } from "@nestjs/common";
import { ForgeController } from "./forge.controller";

@Module({ controllers: [ForgeController] })
export class ForgeModule {}
